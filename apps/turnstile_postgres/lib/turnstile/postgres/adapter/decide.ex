defmodule Turnstile.Postgres.Adapter.Decide do
  @moduledoc false
  # What the adapter asks the database. One statement per object type in the
  # call, run under the session settings, selecting each object's primary key
  # as text beside the update gate's `USING` expression where the operation
  # has a gate:
  #
  #     SELECT id::text, coalesce((<gate using>), false)
  #     FROM <table> WHERE id::text = ANY($1)
  #
  # Visibility answers the read: the `SELECT` policy of the operation narrows
  # the statement, so a row that comes back is one the subject may see under
  # that operation and a row that does not come back is a denial. The gate
  # answers the write: its expression is the one the database will apply
  # through `WITH CHECK` when the write runs, so an answer given before a
  # write agrees with what the write meets. The statement names the table
  # with no alias, because the database renders a policy's references to its
  # own table qualified by that table's name.
  #
  # Primary keys are compared as text, so an integer key and a string key ask
  # the same question and neither the object's id type nor the schema's has
  # to be known here.
  #
  # A repo that raises is left to raise. The port turns any exception a
  # decider raises into the engine error that denies, so this package names
  # no driver's error, and a driver it does not carry needs no clause of its
  # own.

  alias Turnstile.Answer
  alias Turnstile.Postgres.Adapter.Session
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Core.Name
  alias Turnstile.Postgres.Core.Settings
  alias Turnstile.Postgres.Policy

  @exemption {:exempt, :library}

  @doc "One answer per object, grouped by object type, under one set of settings."
  @spec many(Binding.t(), Catalog.t(), Turnstile.subject(), atom(), [Turnstile.object()], Turnstile.environment()) ::
          {:ok, %{Turnstile.object() => Answer.t()}}
  def many(
        %Binding{} = binding,
        %Catalog{} = catalog,
        {_kind, _account} = subject,
        operation,
        objects,
        %{now: _now} = env
      )
      when is_atom(operation) and is_list(objects) do
    settings = remembered(subject, operation, env)

    if objects == [] do
      {:ok, %{}}
    else
      {:ok, Session.around(binding.repo, settings, fn -> grouped(binding, catalog, operation, objects) end)}
    end
  end

  @doc "The answer for one object."
  @spec one(Binding.t(), Catalog.t(), Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment()) ::
          {:ok, Answer.t()}
  def one(%Binding{} = binding, %Catalog{} = catalog, {_kind, _account} = subject, operation, {_type, _id} = object, env) do
    {:ok, answers} = many(binding, catalog, subject, operation, [object], env)
    {:ok, Map.fetch!(answers, object)}
  end

  @doc """
  The answer a scope gets. The rule the port records is `true`: the
  operation's `SELECT` policy narrows the query when it runs, so the reason
  names that policy and the hash of the settings the database will read,
  which together are what it enforced. An operation with no policy on the
  type denies.
  """
  @spec scope(Binding.t(), Catalog.t(), atom(), atom(), Settings.t()) :: Answer.t()
  def scope(%Binding{} = binding, %Catalog{} = catalog, operation, object_type, %Settings{} = settings)
      when is_atom(operation) and is_atom(object_type) do
    with {_schema, table, _key} <- Binding.target(binding, object_type),
         %Policy{} = policy <- Catalog.scope(catalog, table, operation) do
      verdict(catalog, :allow, :allowed, %{rule: "#{policy.name} settings sha256:#{Settings.hash(settings)}"})
    else
      _no_policy -> verdict(catalog, :deny, :unknown_operation)
    end
  end

  defp remembered(subject, operation, environment) do
    settings = Settings.of(subject, operation, environment)
    :ok = Session.remember(subject, operation, settings)
    settings
  end

  defp grouped(binding, catalog, operation, objects) do
    objects
    |> Enum.group_by(&elem(&1, 0))
    |> Enum.reduce(%{}, fn {type, group}, answers ->
      Map.merge(answers, of_type(binding, catalog, operation, type, group))
    end)
  end

  # An object type no bound schema declares, or one whose key is not a
  # single column, has no statement to run and is denied.
  defp of_type(binding, catalog, operation, type, objects) do
    case Binding.target(binding, type) do
      {_schema, table, key} -> against(binding, catalog, operation, {table, key}, objects)
      nil -> denied(catalog, objects, :deny_by_default)
    end
  end

  defp against(binding, catalog, operation, {table, _key} = target, objects) do
    case Catalog.scope(catalog, table, operation) do
      %Policy{} = scope -> answered(binding, catalog, operation, target, scope, objects)
      nil -> denied(catalog, objects, :unknown_operation)
    end
  end

  defp answered(binding, catalog, operation, {table, _key} = target, scope, objects) do
    gate = Catalog.gate(catalog, table, operation)
    rows = admitted(binding, target, gate, Enum.map(objects, &to_string(elem(&1, 1))))
    Map.new(objects, &{&1, answer(catalog, scope, gate, rows, &1)})
  end

  defp admitted(%Binding{repo: repo}, {table, key}, gate, ids) do
    column = Name.check!(key, :primary_key)
    from = Name.check!(table, :table)
    statement = "SELECT #{column}::text, #{predicate(gate)} FROM #{from} WHERE #{column}::text = ANY($1)"
    %{rows: rows} = repo.query!(statement, [ids], turnstile: @exemption)
    Map.new(rows, fn [id, admitted] -> {id, admitted} end)
  end

  defp predicate(%Policy{using: using}) when is_binary(using), do: "coalesce((#{using}), false)"
  defp predicate(_ungated), do: "true"

  defp answer(catalog, scope, gate, rows, {_type, id}) do
    case Map.fetch(rows, to_string(id)) do
      {:ok, true} -> verdict(catalog, :allow, :allowed, %{rule: scope.name})
      {:ok, _refused} -> verdict(catalog, :deny, :rule_denied, %{rule: refusing(gate, scope)})
      :error -> verdict(catalog, :deny, :rule_denied, %{rule: scope.name})
    end
  end

  defp refusing(%Policy{name: name}, _scope), do: name
  defp refusing(nil, %Policy{name: name}), do: name

  defp denied(catalog, objects, reason) do
    Map.new(objects, &{&1, verdict(catalog, :deny, reason)})
  end

  defp verdict(%Catalog{version: version}, verdict, reason, meta \\ %{}) do
    %Answer{verdict: verdict, reason: reason, version: version, meta: meta}
  end
end
