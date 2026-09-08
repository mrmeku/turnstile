defmodule Turnstile.Code.Rule do
  @moduledoc """
  A protected schema's rule for one subject and operation, built from the
  policy's clauses as `dynamic` expressions over the protected row: each
  grant is a membership test against a subquery of its relationship schema,
  each predicate is the function's result, and the whole is any grant and
  every predicate. Building runs no query; `dynamic/1` is the rule `scope`
  returns and the clause map is what `Turnstile.Code.Decide` selects.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Policy
  alias Turnstile.Code.Policy.Clause
  alias Turnstile.Code.Policy.Object
  alias Turnstile.Code.Version
  alias Turnstile.Environment
  alias Turnstile.Reason
  alias Turnstile.Schema
  alias Turnstile.Schema.Relationship
  alias Turnstile.Subject

  @enforce_keys [:policy, :schema, :operation, :roles, :grants, :predicates, :version]
  defstruct @enforce_keys

  @typedoc "A clause name and its expression over the protected row."
  @type clause :: {atom(), Ecto.Query.dynamic_expr()}

  @type t :: %__MODULE__{
          policy: Policy.t(),
          schema: module(),
          operation: atom(),
          roles: [atom()],
          grants: [clause()],
          predicates: [clause()],
          version: String.t()
        }

  @doc """
  Build the rule, or the deny answer when the policy has no object of the
  type or no role permits the operation, or `{:error, detail}` when a
  predicate returned neither a `dynamic` nor a boolean.
  """
  @spec build(Policy.t(), Subject.t(), atom(), atom(), Environment.t()) ::
          {:ok, t()} | {:error, Answer.t() | String.t()}
  def build(policy, %Subject{} = subject, operation, type, %Environment{} = environment)
      when is_atom(policy) and is_atom(operation) and is_atom(type) do
    version = Version.ref(policy)

    with {:ok, %Object{} = object} <- object(policy, type, version),
         {:ok, roles} <- roles(policy, operation, version),
         {:ok, predicates} <- predicates(object, subject, environment) do
      {:ok, new(policy, object, operation, roles, grants(object, subject, roles), predicates, version)}
    end
  end

  @doc "The whole rule: any grant and every predicate."
  @spec dynamic(t()) :: Ecto.Query.dynamic_expr()
  def dynamic(%__MODULE__{grants: grants, predicates: predicates}) do
    any = Enum.reduce(grants, dynamic([_row], false), fn {_name, grant}, acc -> dynamic([row], ^acc or ^grant) end)
    Enum.reduce(predicates, any, fn {_name, predicate}, acc -> dynamic([row], ^acc and ^predicate) end)
  end

  @doc "The rule's clauses by name, for a select."
  @spec clauses(t()) :: %{atom() => Ecto.Query.dynamic_expr()}
  def clauses(%__MODULE__{grants: grants, predicates: predicates}), do: Map.new(grants ++ predicates)

  @doc "The answer a scope carries: allowed by the rule's clauses, by name."
  @spec answer(t()) :: Answer.t()
  def answer(%__MODULE__{grants: grants, predicates: predicates, version: version}) do
    names = Enum.map_join(grants ++ predicates, ", ", fn {name, _expression} -> Atom.to_string(name) end)
    %Answer{verdict: :allow, reason: Reason.allowed(names), policy_version: version, applied_position: nil}
  end

  @doc "The deny answer for a reason."
  @spec deny(Reason.t(), String.t()) :: Answer.t()
  def deny(%Reason{} = reason, version) when is_binary(version) do
    %Answer{verdict: :deny, reason: reason, policy_version: version, applied_position: nil}
  end

  @doc "The one column of a schema's primary key."
  @spec primary_key(module()) :: atom()
  def primary_key(schema) when is_atom(schema) do
    case schema.__schema__(:primary_key) do
      [key] -> key
      keys -> raise ArgumentError, "#{inspect(schema)} has primary key #{inspect(keys)}; rules need one column"
    end
  end

  defp new(policy, %Object{schema: schema}, operation, roles, grants, predicates, version) do
    %__MODULE__{
      policy: policy,
      schema: schema,
      operation: operation,
      roles: roles,
      grants: grants,
      predicates: predicates,
      version: version
    }
  end

  defp grants(%Object{schema: schema, clauses: clauses}, subject, roles) do
    for %Clause{kind: :grant} = clause <- clauses, do: {clause.name, grant(clause, schema, subject, roles)}
  end

  defp object(policy, type, version) do
    case Policy.object_of(policy, type) do
      %Object{} = object -> {:ok, object}
      nil -> {:error, deny(Reason.deny_by_default(), version)}
    end
  end

  defp roles(policy, operation, version) do
    case Policy.roles_for(policy, operation) do
      [] -> {:error, deny(Reason.unknown_operation(operation), version)}
      roles -> {:ok, roles}
    end
  end

  defp predicates(%Object{clauses: clauses}, subject, environment) do
    step = fn clause, {:ok, acc} -> collect(predicate(clause, subject, environment), clause.name, acc) end

    with {:ok, reversed} <- Enum.reduce_while(Enum.filter(clauses, &(&1.kind == :predicate)), {:ok, []}, step) do
      {:ok, Enum.reverse(reversed)}
    end
  end

  defp collect({:ok, expression}, name, acc), do: {:cont, {:ok, [{name, expression} | acc]}}
  defp collect({:error, detail}, _name, _acc), do: {:halt, {:error, detail}}

  defp predicate(%Clause{name: name, predicate: fun}, subject, environment) do
    case fun.(subject, environment) do
      %Ecto.Query.DynamicExpr{} = expression -> {:ok, expression}
      true -> {:ok, dynamic([_row], true)}
      false -> {:ok, dynamic([_row], false)}
      other -> {:error, "predicate #{name} returned #{inspect(other)}, not a dynamic or a boolean"}
    end
  end

  # The grant holds when the protected row's `on` column is among the object
  # columns of the relationship rows that name the subject with a role that
  # permits the operation.
  defp grant(%Clause{source: source} = clause, schema, %Subject{id: subject_id}, roles) do
    %Relationship{subject: subject_column, object: object_column} = relationship = Schema.relationship_of(source)
    on = clause.on || primary_key(schema)

    case role_filter(clause, relationship, roles) do
      :none ->
        dynamic([_row], false)

      :all ->
        members = from(r in source, where: field(r, ^subject_column) == ^subject_id, select: field(r, ^object_column))
        dynamic([row], field(row, ^on) in subquery(members))

      {:column, role_column} ->
        members =
          from(r in source,
            where: field(r, ^subject_column) == ^subject_id and field(r, ^role_column) in ^roles,
            select: field(r, ^object_column)
          )

        dynamic([row], field(row, ^on) in subquery(members))
    end
  end

  defp role_filter(%Clause{as: as}, _relationship, roles) when is_atom(as) and not is_nil(as) do
    if as in roles, do: :all, else: :none
  end

  defp role_filter(%Clause{role: role}, _relationship, _roles) when is_atom(role) and not is_nil(role) do
    {:column, role}
  end

  defp role_filter(%Clause{}, %Relationship{attributes: [role]}, _roles), do: {:column, role}
end
