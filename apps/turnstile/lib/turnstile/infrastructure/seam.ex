defmodule Turnstile.Infrastructure.Seam do
  # What every override `use Turnstile.Repo` defines calls. One function per
  # bucket of `Turnstile.Infrastructure.Surface`: `query/5` for the query bucket,
  # `bulk/5` for `update_all` and `delete_all`, `write/5` and `write_all/5`
  # for the write bucket, `raw/4` for raw SQL, and `prepare/4` behind
  # `prepare_query/3`, where every query, including the ones `preload`
  # generates, is judged.
  #
  # A write to an audited schema on an application-role repo runs in a
  # transaction, and the change it made is published inside that transaction
  # (`Turnstile.Change`), so a handler that writes from the same repository
  # joins it. A read of a protected schema under a decision publishes what
  # it returned after it returns (`Turnstile.Access`). The owner-role repo
  # records nothing: it is the library's own channel.
  @moduledoc false

  alias Turnstile.Access
  alias Turnstile.Change
  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Domain.Matching
  alias Turnstile.Domain.Mediation
  alias Turnstile.Domain.Source
  alias Turnstile.Error
  alias Turnstile.Id
  alias Turnstile.Infrastructure.Caller
  alias Turnstile.Infrastructure.Option
  alias Turnstile.Schema

  @type call :: Mediation.call()
  @type continue :: (keyword() -> term())

  @doc """
  The query bucket: resolve the option, wrap the call, and publish what a
  read under a decision returned; the query itself is judged in `prepare/4`.
  """
  @spec query(module(), call(), term(), keyword(), continue()) :: term()
  def query(repo, call, target, opts, continue) when is_atom(repo) and is_list(opts) do
    root = Source.root(target)
    {mediation, opts} = Option.resolve(repo, call, root, opts)
    result = around(repo, mediation, Source.to_query(target), fn -> continue.(opts) end)
    :ok = accessed(repo, call, root, mediation, result)
    result
  end

  @doc "`update_all` and `delete_all`: the query bucket, plus the refusal of a bulk write to an audited schema."
  @spec bulk(module(), call(), term(), keyword(), continue()) :: term()
  def bulk(repo, call, queryable, opts, continue) when is_atom(repo) and is_list(opts) do
    root = Source.root(queryable)
    {mediation, opts} = Option.resolve(repo, call, root, opts)
    :ok = refuse_bulk(repo, call, root)
    around(repo, mediation, Source.to_query(queryable), fn -> continue.(opts) end)
  end

  @doc "The write bucket for one row: judge the root, refuse an upsert on a fact schema, record, wrap."
  @spec write(module(), call(), Ecto.Changeset.t() | struct(), keyword(), continue()) :: term()
  def write(repo, call, changeset_or_struct, opts, continue) when is_atom(repo) and is_list(opts) do
    changeset = Ecto.Changeset.change(changeset_or_struct)
    schema = changeset.data.__struct__
    {mediation, opts} = Option.resolve(repo, call, schema, opts)
    :ok = Matching.admit(schema, mediation, caller(repo))
    :ok = refuse_upsert(call, schema, opts)

    around(repo, mediation, changeset, fn ->
      Option.with_ambient(mediation, fn -> recorded(repo, call, changeset, mediation, opts, continue) end)
    end)
  end

  @doc "`insert_all`: judge the root, refuse an upsert or a bulk insert into an audited schema, wrap."
  @spec write_all(module(), call(), term(), keyword(), continue()) :: term()
  def write_all(repo, call, source, opts, continue) when is_atom(repo) and is_list(opts) do
    root = Source.root(source)
    {mediation, opts} = Option.resolve(repo, call, root, opts)
    :ok = Matching.admit(schema_of(root), mediation, caller(repo))
    :ok = refuse_upsert(call, schema_of(root), opts)
    :ok = refuse_bulk(repo, call, root)
    around(repo, mediation, Source.to_query(source), fn -> continue.(opts) end)
  end

  @doc "The raw bucket: an exemption or nothing."
  @spec raw(module(), call(), keyword(), continue()) :: term()
  def raw(repo, {name, arity} = call, opts, continue) when is_atom(repo) and is_list(opts) do
    case Option.resolve(repo, call, nil, opts) do
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
        :ok = Matching.judge(query, mediation, caller(repo))
        {query, opts}

      _other ->
        :ok = Matching.judge(query, Mediation.empty({operation, arity(operation)}), caller(repo))
        {query, opts}
    end
  end

  # What a refusal names as the module that made the call, read from the
  # stack only where there is a refusal to name.
  defp caller(repo), do: fn -> Caller.module(repo) end

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

  # The access event: a read of a protected schema under a decision, after
  # it returned. An exempt read, a read the owner-role repo made, and a read
  # of a schema that declares no object type publish nothing.
  defp accessed(repo, call, root, %Mediation{decision: %Decision{} = decision}, result) when is_atom(root) do
    if Schema.object_type_of(root) do
      Access.publish(repo, root, call, result, decision, config!().clock.())
    else
      :ok
    end
  end

  defp accessed(_repo, _call, _root, _mediation, _result), do: :ok

  defp recorded(repo, {name, _arity}, changeset, mediation, opts, continue) do
    schema = changeset.data.__struct__

    if audited?(repo, schema) do
      transactional(repo, fn -> record(repo, action(name, changeset), changeset, mediation, opts, continue) end)
    else
      continue.(opts)
    end
  end

  defp record(repo, action, changeset, mediation, opts, continue) do
    schema = changeset.data.__struct__
    result = continue.(opts)

    case written(result) do
      nil ->
        result

      row ->
        :ok = published(repo, schema, action, changeset.data, row, stamp(mediation))
        result
    end
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
    %{by: decision.subject, decision_id: decision.id, operation_id: decision.operation_id, at: config!().clock.()}
  end

  defp stamp(_mediation) do
    %{by: Change.library(), decision_id: nil, operation_id: Id.new(), at: config!().clock.()}
  end

  # An audited write runs inside a transaction so the write and the change
  # it publishes commit together; a write that reports an error rolls it
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
              "Repo.#{name}/#{arity} with on_conflict: on #{inspect(schema)} is an upsert of fact fields; " <>
                "write the rows one at a time"
            )
    else
      :ok
    end
  end

  # A bulk write to an audited schema is refused: one statement changes many
  # rows, and the change each row made cannot be read back from it, so no
  # caller of an application-role repo may make one. The owner-role repo is
  # the library's own channel and records nothing, so it passes.
  defp refuse_bulk(repo, {name, arity}, root) do
    schema = schema_of(root)

    if repo.__turnstile__(:role) != :owner and Schema.audited?(schema) do
      raise Error.invalid(
              :bulk_write,
              "Repo.#{name}/#{arity} on #{inspect(schema)} is a bulk write to an audited schema; " <>
                "write the rows one at a time"
            )
    else
      :ok
    end
  end

  defp schema_of(root) when is_atom(root), do: root
  defp schema_of(_root), do: nil

  defp arity(:update_all), do: 3
  defp arity(_operation), do: 2
end
