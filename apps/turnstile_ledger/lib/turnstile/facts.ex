defmodule Turnstile.Facts do
  @moduledoc """
  Bulk writes to fact schemas. A plain `Repo.update_all` on a fact field is
  refused when a ledger is configured, because a thousand facts would change
  with nothing in the ledger to say so. These three calls are what an
  application uses instead, and they record what they write.

  Each is one transaction. The rows that would change are narrowed by a
  null-safe difference condition, so a write to the value a row already
  holds touches nothing; the rows are read under the ledger's lock, the
  write returns the rows it touched, the fact mapping turns the values
  before and after into events, and one append takes their positions from
  the counter row in one statement. An append that fails rolls the write
  back and comes out as `{:error, %Turnstile.Error.Engine{}}`.

  Each is also one span on `[:turnstile, :bulk, :start | :stop | :exception]`
  whose stop carries a `Turnstile.Facts.Record`, the audit record of the
  write. A write that touches no fact field, and any write in ledger mode
  none, is a plain bulk write: one statement, no rows back, no events, and
  the record still.

  Every call takes the same options, `schema/0` below.
  """

  use Boundary, top_level?: true, deps: [Ecto, Turnstile, Turnstile.Ledger.Dialect], exports: [Record]

  import Ecto.Query, only: [dynamic: 1, dynamic: 2, from: 2, where: 3]

  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Facts.Context
  alias Turnstile.Facts.Record
  alias Turnstile.Id
  alias Turnstile.Repo
  alias Turnstile.Schema
  alias Turnstile.Subject

  @span [:turnstile, :bulk]

  @schema NimbleOptions.new!(
            turnstile: [
              type: {:custom, __MODULE__, :validate_turnstile, []},
              required: true,
              doc: "The decision the write runs under, or a declared exemption."
            ],
            repo: [
              type: :atom,
              doc: "The repo to write through; the ledger's own repo when absent."
            ],
            prefix: [
              type: :string,
              doc: "The query prefix, as the repo's own calls take it."
            ]
          )

  @doc "The schema of the options the three calls take. Options: #{NimbleOptions.docs(@schema)}"
  @spec schema() :: NimbleOptions.t()
  def schema, do: @schema

  @doc """
  Answer whether the `:turnstile` option is a decision or a declared
  exemption. `Turnstile.Repo.Mediation` holds that answer, and this call
  reaches it when an option is validated rather than when this module is
  compiled.
  """
  @spec validate_turnstile(term()) :: {:ok, term()} | {:error, String.t()}
  def validate_turnstile(value), do: Repo.Mediation.validate_option(value)

  @doc "The three telemetry events of a bulk write, in the order they happen."
  @spec events() :: [[atom()]]
  def events, do: Enum.map([:start, :stop, :exception], &List.insert_at(@span, -1, &1))

  @doc """
  Update every row the queryable admits, as `Repo.update_all/3` does, and
  append one event per fact the update changed. A set of a fact field to the
  value a row already holds is not a change; a computed set, `inc` among
  them, is a change on every row it reaches.
  """
  @spec bulk_update(Ecto.Queryable.t(), keyword(), keyword()) :: {:ok, Record.t()} | {:error, Error.Engine.t()}
  def bulk_update(queryable, updates, opts) when is_list(updates) and is_list(opts) do
    context = context!(queryable, opts)
    span(:update, context, fn -> update(context, queryable, updates) end)
  end

  @doc "Delete every row the queryable admits, as `Repo.delete_all/2` does, and append one event per fact that goes with it."
  @spec bulk_delete(Ecto.Queryable.t(), keyword()) :: {:ok, Record.t()} | {:error, Error.Engine.t()}
  def bulk_delete(queryable, opts) when is_list(opts) do
    context = context!(queryable, opts)
    span(:delete, context, fn -> delete(context, queryable) end)
  end

  @doc "Insert the entries, as `Repo.insert_all/3` does, and append one event per fact they state."
  @spec bulk_insert(module(), [map() | keyword()], keyword()) :: {:ok, Record.t()} | {:error, Error.Engine.t()}
  def bulk_insert(schema, entries, opts) when is_atom(schema) and is_list(entries) and is_list(opts) do
    context = context!(schema, opts)
    span(:insert, context, fn -> insert(context, entries) end)
  end

  defp update(context, queryable, updates) do
    if recorded?(context) and Repo.Facts.touched(context.schema, set_fields(updates)) != [] do
      transactional(context, fn -> recorded_update(context, queryable, updates) end)
    else
      {count, nil} = context.repo.update_all(queryable, updates, context.opts)
      {:ok, record(context, :update, count, [])}
    end
  end

  defp delete(context, queryable) do
    if recorded?(context) and Schema.fact_schema?(context.schema) do
      transactional(context, fn -> recorded_delete(context, queryable) end)
    else
      {count, nil} = context.repo.delete_all(queryable, context.opts)
      {:ok, record(context, :delete, count, [])}
    end
  end

  defp insert(context, entries) do
    if recorded?(context) and Schema.fact_schema?(context.schema) do
      transactional(context, fn -> recorded_insert(context, entries) end)
    else
      {count, nil} = context.repo.insert_all(context.schema, entries, context.opts)
      {:ok, record(context, :insert, count, [])}
    end
  end

  # The rows before the write are read under the lock in the same
  # transaction, so nothing changes them between the read and the write.
  defp recorded_update(context, queryable, updates) do
    narrowed = narrow(queryable, context, updates)
    olds = locked(context, narrowed)
    :returning = rows_back!(context)
    {_count, news} = context.repo.update_all(returning(narrowed), updates, context.opts)
    settle(context, :update, length(news), changes(context, olds, news))
  end

  defp recorded_delete(context, queryable) do
    {_count, rows} = context.repo.delete_all(returning(queryable), context.opts)
    events = Enum.flat_map(rows, &Repo.Facts.events(context.schema, &1, nil, context.stamp))
    settle(context, :delete, length(rows), events)
  end

  defp recorded_insert(context, entries) do
    opts = Keyword.put(context.opts, :returning, true)
    {_count, rows} = context.repo.insert_all(context.schema, entries, opts)
    events = Enum.flat_map(rows, &Repo.Facts.events(context.schema, nil, &1, context.stamp))
    settle(context, :insert, length(rows), events)
  end

  defp changes(context, olds, news) do
    before = Map.new(olds, &{Ecto.primary_key(&1), &1})
    Enum.flat_map(news, &Repo.Facts.events(context.schema, before[Ecto.primary_key(&1)], &1, context.stamp))
  end

  defp settle(context, operation, count, []), do: {:ok, record(context, operation, count, [])}

  defp settle(context, operation, count, events) do
    case context.ledger.append(context.options, events) do
      {:ok, stamped} -> {:ok, record(context, operation, count, stamped)}
      {:error, %Error.Engine{} = error} -> context.repo.rollback(error)
    end
  end

  defp locked(context, queryable) do
    query = Ecto.Queryable.to_query(queryable)
    context.repo.all(%{query | lock: Keyword.get(context.options, :lock, "FOR UPDATE")}, context.opts)
  end

  defp returning(queryable), do: from(r in queryable, select: r)

  # A row differs from what the write would set when the column is null and
  # the value is not, or the column holds something else. A computed set
  # reaches every row, so a write that has one narrows nothing, and so does a
  # write that sets a column no fact declares beside a fact column.
  defp narrow(queryable, context, updates) do
    fields = set_fields(updates)
    facts = Repo.Facts.touched(context.schema, fields)

    if Keyword.keys(updates) == [:set] and facts == fields do
      where(queryable, [r], ^difference(updates[:set]))
    else
      queryable
    end
  end

  defp difference(set) do
    Enum.reduce(set, dynamic(false), fn {field, value}, condition ->
      dynamic([r], ^condition or ^differs(field, value))
    end)
  end

  defp differs(field, nil), do: dynamic([r], not is_nil(field(r, ^field)))
  defp differs(field, value), do: dynamic([r], is_nil(field(r, ^field)) or field(r, ^field) != ^value)

  defp set_fields(updates) do
    updates
    |> Keyword.values()
    |> Enum.flat_map(&Keyword.keys/1)
    |> Enum.uniq()
  end

  defp rows_back!(context) do
    dialect = Keyword.get(context.options, :dialect, Turnstile.Ledger.Dialect.Postgres)

    case dialect.rows_back() do
      :returning ->
        :returning

      other ->
        raise Error.Unsupported,
          adapter: dialect,
          feature: :bulk_write,
          note: "the bulk API needs a dialect whose write returns its rows, and this one answers #{inspect(other)}"
    end
  end

  defp record(context, operation, count, events) do
    positions = Enum.map(events, & &1.position)

    %Record{
      operation: operation,
      schema: context.schema,
      operation_id: context.stamp.operation_id,
      count: count,
      min_position: Enum.min(positions, fn -> nil end),
      max_position: Enum.max(positions, fn -> nil end),
      by: context.stamp.by,
      at: context.stamp.at
    }
  end

  defp span(operation, context, fun) do
    :telemetry.span(@span, %{operation: operation, schema: context.schema}, fn ->
      result = fun.()
      {result, stopped(result)}
    end)
  end

  defp stopped({:ok, %Record{} = record}), do: %{record: record}
  defp stopped({:error, error}), do: %{error: error}

  defp transactional(context, fun) do
    case context.repo.transaction(fun) do
      {:ok, result} -> result
      {:error, %Error.Engine{} = error} -> {:error, error}
    end
  end

  defp recorded?(%Context{ledger: :none}), do: false
  defp recorded?(%Context{}), do: true

  defp context!(queryable, opts) do
    opts = NimbleOptions.validate!(opts, @schema)
    config = config!()
    {ledger, options} = ledger(config.ledger)

    %Context{
      repo: repo!(opts, options),
      schema: schema!(queryable),
      ledger: ledger,
      options: options,
      stamp: stamp(config, opts[:turnstile]),
      opts: Keyword.take(opts, [:turnstile, :prefix])
    }
  end

  defp ledger(:none), do: {:none, []}
  defp ledger({module, options}), do: {module, options}

  defp repo!(opts, options) do
    opts[:repo] || Keyword.get(options, :repo) ||
      raise Error.Invalid,
        what: :bulk_write,
        detail: "no repo: the ledger's options name none, so the call needs repo: MyApp.Repo"
  end

  defp schema!(module) when is_atom(module) and not is_nil(module), do: module

  defp schema!(%Ecto.Query{from: %{source: {_source, schema}}}) when is_atom(schema) and not is_nil(schema), do: schema

  defp schema!(other) do
    raise Error.Invalid,
      what: :bulk_write,
      detail: "a bulk write needs a schema or a query on one, got: #{inspect(other)}"
  end

  defp stamp(config, %Decision{} = decision) do
    %{by: decision.subject, operation_id: decision.operation_id, at: config.clock.now()}
  end

  defp stamp(config, {:exempt, _reason}) do
    %{by: Subject.library(), operation_id: Id.new(), at: config.clock.now()}
  end

  defp config! do
    case Config.resolve() do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end
end
