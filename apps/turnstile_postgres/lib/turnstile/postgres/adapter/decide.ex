defmodule Turnstile.Postgres.Adapter.Decide do
  @moduledoc false
  # What the adapter asks the database. One statement per decision, run
  # under the session settings, selecting the update gate's `USING`
  # expression for the row asked about where the operation has a gate:
  #
  #     SELECT coalesce((<gate using>), false)
  #     FROM <table> WHERE id::text = $1
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

  @doc "The answer for one object, under the settings of the call, which the session remembers."
  @spec one(Binding.t(), Catalog.t(), Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment()) ::
          {:ok, Answer.t()}
  def one(
        %Binding{} = binding,
        %Catalog{} = catalog,
        {_kind, _account} = subject,
        operation,
        {type, id},
        %{now: _now} = env
      )
      when is_atom(operation) do
    settings = remembered(subject, operation, env)
    {:ok, Session.around(binding.repo, settings, fn -> of_type(binding, catalog, operation, type, id) end)}
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

  # An object type no bound schema declares, or one whose key is not a
  # single column, has no statement to run and is denied.
  defp of_type(binding, catalog, operation, type, id) do
    case Binding.target(binding, type) do
      {_schema, table, key} -> against(binding, catalog, operation, {table, key}, id)
      nil -> verdict(catalog, :deny, :deny_by_default)
    end
  end

  defp against(binding, catalog, operation, {table, _key} = target, id) do
    case Catalog.scope(catalog, table, operation) do
      %Policy{} = scope -> answered(binding, catalog, operation, target, scope, id)
      nil -> verdict(catalog, :deny, :unknown_operation)
    end
  end

  defp answered(binding, catalog, operation, {table, _key} = target, scope, id) do
    gate = Catalog.gate(catalog, table, operation)
    answer(catalog, scope, gate, admitted(binding, target, gate, to_string(id)))
  end

  defp admitted(%Binding{repo: repo}, {table, key}, gate, id) do
    column = Name.check!(key, :primary_key)
    from = Name.check!(table, :table)
    statement = "SELECT #{predicate(gate)} FROM #{from} WHERE #{column}::text = $1"

    case repo.query!(statement, [id], turnstile: @exemption) do
      %{rows: [[admitted]]} -> {:ok, admitted}
      %{rows: []} -> :error
    end
  end

  defp predicate(%Policy{using: using}) when is_binary(using), do: "coalesce((#{using}), false)"
  defp predicate(_ungated), do: "true"

  defp answer(catalog, scope, _gate, {:ok, true}), do: verdict(catalog, :allow, :allowed, %{rule: scope.name})

  defp answer(catalog, scope, gate, {:ok, _refused}) do
    verdict(catalog, :deny, :rule_denied, %{rule: refusing(gate, scope)})
  end

  defp answer(catalog, scope, _gate, :error), do: verdict(catalog, :deny, :rule_denied, %{rule: scope.name})

  defp refusing(%Policy{name: name}, _scope), do: name
  defp refusing(nil, %Policy{name: name}), do: name

  defp verdict(%Catalog{version: version}, verdict, reason, meta \\ %{}) do
    %Answer{verdict: verdict, reason: reason, version: version, meta: meta}
  end
end
