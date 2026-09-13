defmodule Turnstile.Repo.Seam do
  @moduledoc """
  What every override `use Turnstile.Repo` defines calls. One function per
  bucket of `Turnstile.Repo.Surface`: `query/5` for the query bucket,
  `bulk/6` for `update_all` and `delete_all`, `write/5` and `write_all/6`
  for the write bucket, `raw/4` for raw SQL, and `prepare/4` behind
  `prepare_query/3`, where every query, including the ones `preload`
  generates, is judged.

  A write to an audited schema on an application-role repo runs in a
  transaction, and the change it made is published inside that transaction
  (`Turnstile.Repo.Change`). Where a ledger is configured, a write to a
  fact schema runs in the same transaction with the row re-read under the
  ledger's lock clause and the events appended. The owner-role repo records
  nothing: it is the library's own channel.
  """

  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.Repo.Caller
  alias Turnstile.Repo.Change
  alias Turnstile.Repo.Facts
  alias Turnstile.Repo.Matching
  alias Turnstile.Repo.Mediation
  alias Turnstile.Repo.Source
  alias Turnstile.Schema

  @bulk_api "Turnstile.Facts.bulk_insert/3, Turnstile.Facts.bulk_update/3, or Turnstile.Facts.bulk_delete/2 in turnstile_ledger"

  @type call :: Mediation.call()
  @type continue :: (keyword() -> term())

  @doc "The query bucket: resolve the option, then wrap the call; the query itself is judged in `prepare/4`."
  @spec query(module(), call(), term(), keyword(), continue()) :: term()
  def query(repo, call, target, opts, continue) when is_atom(repo) and is_list(opts) do
    {mediation, opts} = Mediation.resolve(repo, call, Source.root(target), opts)
    around(repo, mediation, Source.to_query(target), fn -> continue.(opts) end)
  end

  @doc "`update_all` and `delete_all`: the query bucket, plus the refusal of a plain bulk write to fact fields."
  @spec bulk(module(), call(), term(), keyword() | nil, keyword(), continue()) :: term()
  def bulk(repo, call, queryable, updates, opts, continue) when is_atom(repo) and is_list(opts) do
    root = Source.root(queryable)
    {mediation, opts} = Mediation.resolve(repo, call, root, opts)
    :ok = refuse_bulk(repo, call, root, bulk_fields(root, updates), mediation)
    around(repo, mediation, Source.to_query(queryable), fn -> continue.(opts) end)
  end

  @doc "The write bucket for one row: judge the root, refuse an upsert on a fact schema, record, wrap."
  @spec write(module(), call(), Ecto.Changeset.t() | struct(), keyword(), continue()) :: term()
  def write(repo, call, changeset_or_struct, opts, continue) when is_atom(repo) and is_list(opts) do
    changeset = Ecto.Changeset.change(changeset_or_struct)
    schema = changeset.data.__struct__
    {mediation, opts} = Mediation.resolve(repo, call, schema, opts)
    :ok = Matching.admit(schema, mediation, repo)
    :ok = refuse_upsert(call, schema, opts)

    around(repo, mediation, changeset, fn ->
      Mediation.with_ambient(mediation, fn -> recorded(repo, call, changeset, mediation, opts, continue) end)
    end)
  end

  @doc "`insert_all`: judge the root, refuse an upsert or a plain bulk insert on a fact schema, wrap."
  @spec write_all(module(), call(), term(), [map() | keyword()] | Ecto.Query.t(), keyword(), continue()) :: term()
  def write_all(repo, call, source, entries, opts, continue) when is_atom(repo) and is_list(opts) do
    root = Source.root(source)
    {mediation, opts} = Mediation.resolve(repo, call, root, opts)
    :ok = Matching.admit(schema_of(root), mediation, repo)
    :ok = refuse_upsert(call, schema_of(root), opts)
    :ok = refuse_bulk(repo, call, root, entry_fields(root, entries), mediation)
    around(repo, mediation, Source.to_query(source), fn -> continue.(opts) end)
  end

  @doc "The raw bucket: an exemption or nothing."
  @spec raw(module(), call(), keyword(), continue()) :: term()
  def raw(repo, {name, arity} = call, opts, continue) when is_atom(repo) and is_list(opts) do
    case Mediation.resolve(repo, call, nil, opts) do
      {%Mediation{exemption: %Turnstile.Exemption{}}, opts} ->
        continue.(opts)

      {%Mediation{decision: %Decision{}}, _opts} ->
        raise Error.invalid(:turnstile, "Repo.#{name}/#{arity} takes an exemption, not a decision")

      {%Mediation{}, _opts} ->
        raise Mediation.unmediated(function: name, arity: arity, schema: nil, caller: Caller.module(repo))
    end
  end

  @doc "Behind `prepare_query/3`: judge the query under the mediation the override put in the options."
  @spec prepare(module(), atom(), Ecto.Query.t(), keyword()) :: {Ecto.Query.t(), keyword()}
  def prepare(repo, operation, %Ecto.Query{} = query, opts) when is_atom(repo) and is_list(opts) do
    case Keyword.get(opts, :turnstile) do
      %Mediation{} = mediation ->
        :ok = Matching.judge(query, mediation, repo)
        {query, opts}

      _other ->
        :ok = Matching.judge(query, %{Mediation.empty({operation, arity(operation)}) | caller: Caller.module(repo)}, repo)
        {query, opts}
    end
  end

  # Calls the adapter's around_query/3 when a decision is in force and the
  # adapter defines it; otherwise runs the call.
  defp around(_repo, %Mediation{decision: %Decision{} = decision}, subject, fun) do
    {adapter, _options} = Config.adapter(config!())

    if function_exported?(adapter, :around_query, 3) do
      adapter.around_query(subject, decision, fun)
    else
      fun.()
    end
  end

  defp around(_repo, _mediation, _subject, fun), do: fun.()

  defp recorded(repo, {name, _arity}, changeset, mediation, opts, continue) do
    schema = changeset.data.__struct__
    ledger = ledger(repo, schema)

    if ledger == :none and not audited?(repo, schema) do
      continue.(opts)
    else
      action = action(name, changeset)
      transactional(repo, fn -> record(repo, action, changeset, mediation, opts, continue, ledger) end)
    end
  end

  defp record(repo, action, changeset, mediation, opts, continue, ledger) do
    schema = changeset.data.__struct__
    old = reread(repo, ledger, action, changeset, opts)
    result = continue.(opts)

    case written(result) do
      nil ->
        result

      row ->
        stamp = stamp(mediation)
        :ok = appended(ledger, schema, old, new(action, old, changeset, row), stamp)
        :ok = published(repo, schema, action, changeset.data, row, stamp)
        result
    end
  end

  defp reread(_repo, :none, _action, _changeset, _opts), do: nil

  defp reread(repo, {_ledger, options}, action, changeset, opts) do
    if action in [:update, :delete], do: Facts.reread(repo, changeset.data, options[:lock], opts)
  end

  defp appended(:none, _schema, _old, _new, _stamp), do: :ok

  defp appended({ledger, options}, schema, old, new, stamp) do
    append(ledger, options, Facts.events(schema, old, new, stamp))
  end

  # The event a consumer builds a record from, published inside the
  # transaction the write runs in, with the row the caller loaded as the
  # value before the change.
  defp published(repo, schema, action, data, row, stamp) do
    if audited?(repo, schema) do
      {old, new} = sides(action, data, row)
      Change.publish(schema, operation(action), old, new, stamp)
    else
      :ok
    end
  end

  defp sides(:insert, _data, row), do: {nil, row}
  defp sides(:update, data, row), do: {data, row}
  defp sides(:delete, data, _row), do: {data, nil}

  defp operation(:insert), do: :create
  defp operation(action), do: action

  # The row after the write: nothing after a delete, the re-read row with
  # the changes applied after an update, the returned row after an insert.
  defp new(:delete, _old, _changeset, _row), do: nil
  defp new(:update, %{} = old, changeset, _row), do: Map.merge(old, changeset.changes)
  defp new(_action, _old, _changeset, row), do: row

  defp append(_ledger, _options, []), do: :ok

  defp append(ledger, options, events) do
    case ledger.append(options, events) do
      {:ok, _stamped} -> :ok
      {:error, error} when is_exception(error) -> raise error
    end
  end

  defp written({:ok, %{__struct__: _schema} = row}), do: row
  defp written(%{__struct__: schema} = row) when schema != Ecto.Changeset, do: row
  defp written(_other), do: nil

  defp action(name, changeset) do
    case Atom.to_string(name) do
      "insert_or_update" <> _bang -> if changeset.data.__meta__.state == :loaded, do: :update, else: :insert
      "insert" <> _bang -> :insert
      "update" <> _bang -> :update
      "delete" <> _bang -> :delete
    end
  end

  defp stamp(%Mediation{decision: %Decision{} = decision}) do
    %{by: decision.subject, operation_id: decision.operation_id, at: config!().clock.()}
  end

  defp stamp(_mediation), do: %{by: FactEvent.library(), operation_id: Id.new(), at: config!().clock.()}

  # A fact write runs inside a transaction so the re-read's lock, the write,
  # and the append commit together; a write that reports an error rolls it
  # back and the error comes out as the write returned it.
  defp transactional(repo, fun) do
    if repo.in_transaction?(), do: fun.(), else: in_transaction(repo, fun)
  end

  defp in_transaction(repo, fun) do
    case repo.transaction(fn -> settle(repo, fun.()) end) do
      {:ok, result} ->
        result

      {:error, {__MODULE__, result}} ->
        result

      {:error, other} ->
        raise Error,
          reason: :engine_unreachable,
          detail: "#{inspect(repo)} failed during a transaction: " <> inspect(other)
    end
  end

  defp settle(_repo, {:ok, _row} = result), do: result
  defp settle(repo, {:error, _reason} = result), do: repo.rollback({__MODULE__, result})
  defp settle(_repo, result), do: result

  defp ledger(repo, schema) do
    if repo.__turnstile__(:role) == :app and Schema.fact_schema?(schema), do: config!().ledger, else: :none
  end

  # The owner-role repo is the library's own channel, so what it writes is
  # not a change the application made.
  defp audited?(repo, schema), do: repo.__turnstile__(:role) == :app and Schema.audited?(schema)

  defp config! do
    case Config.resolve() do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end

  defp refuse_upsert({name, arity}, schema, opts) do
    if Schema.fact_schema?(schema) and Keyword.get(opts, :on_conflict, :raise) != :raise do
      raise Error.invalid(
              :upsert,
              "Repo.#{name}/#{arity} with on_conflict: on #{inspect(schema)} is an upsert of fact fields; use " <>
                @bulk_api
            )
    else
      :ok
    end
  end

  # A plain bulk write to fact fields is refused when a ledger is configured
  # and the caller is not the library, whose bulk API records what it writes.
  defp refuse_bulk(repo, {name, arity}, root, fields, mediation) do
    schema = schema_of(root)

    cond do
      repo.__turnstile__(:role) == :owner or fields == [] ->
        :ok

      config!().ledger == :none ->
        :ok

      Caller.library?(caller(mediation, repo)) ->
        :ok

      true ->
        raise Error.invalid(
                :bulk_write,
                "Repo.#{name}/#{arity} on #{inspect(schema)} touches fact fields #{inspect(fields)}; use " <> @bulk_api
              )
    end
  end

  defp caller(%Mediation{caller: caller}, _repo) when is_atom(caller) and not is_nil(caller), do: caller
  defp caller(_mediation, repo), do: Caller.module(repo)

  # update_all: the fields its set and inc touch; delete_all: every fact
  # column, because a deleted relationship row is a fact.
  defp bulk_fields(root, nil), do: Facts.touched(schema_of(root) || Turnstile.Repo, all_columns(root))

  defp bulk_fields(root, updates) when is_list(updates) do
    fields =
      updates
      |> Enum.flat_map(fn {_operation, changes} -> Keyword.keys(List.wrap(changes)) end)
      |> Enum.uniq()

    Facts.touched(schema_of(root) || Turnstile.Repo, fields)
  end

  defp entry_fields(root, entries) when is_list(entries) do
    fields =
      entries
      |> Enum.flat_map(&Map.keys(Map.new(&1)))
      |> Enum.uniq()

    Facts.touched(schema_of(root) || Turnstile.Repo, fields)
  end

  defp entry_fields(root, _query), do: Facts.touched(schema_of(root) || Turnstile.Repo, all_columns(root))

  defp all_columns(root) do
    case schema_of(root) do
      nil -> []
      schema -> schema.__schema__(:fields)
    end
  end

  defp schema_of(root) when is_atom(root), do: root
  defp schema_of(_root), do: nil

  defp arity(:update_all), do: 3
  defp arity(_operation), do: 2
end
