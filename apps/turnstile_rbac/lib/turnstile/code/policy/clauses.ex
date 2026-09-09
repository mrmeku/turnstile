defmodule Turnstile.Code.Policy.Clauses do
  @moduledoc """
  The clauses of a policy, built and checked against the schemas they name
  when the policy is read. `Turnstile.Code.Policy` generates a call of
  `object/2` per protected schema, with a `grant/3` or `predicate/3` per
  clause, inside the function the policy module answers `objects/1` with;
  each raises on a declaration the schemas cannot back, so a bad policy
  fails where it is first read.
  """

  alias Turnstile.Code.Policy
  alias Turnstile.Code.Policy.Clause
  alias Turnstile.Code.Policy.Object
  alias Turnstile.Schema
  alias Turnstile.Schema.Relationship

  @grant_schema NimbleOptions.new!(
                  on: [type: :atom, doc: "The protected column the relationship's object column names."],
                  role: [type: :atom, doc: "The relationship column that holds the role."],
                  as: [type: :atom, doc: "The role every row holds, when there is no role column."],
                  through: [
                    type: {:list, {:custom, __MODULE__, :hop, []}},
                    default: [],
                    doc:
                      "The hops from the protected row outward, each `{schema, column}` or `{schema, column, where: fun}`."
                  ]
                )

  @predicate_schema NimbleOptions.new!(
                      only: [type: {:list, :atom}, doc: "The operations the predicate applies to; all when absent."]
                    )

  @doc "The options `grant` accepts."
  @spec grant_schema() :: NimbleOptions.t()
  def grant_schema, do: @grant_schema

  @doc "The options `predicate` accepts."
  @spec predicate_schema() :: NimbleOptions.t()
  def predicate_schema, do: @predicate_schema

  @doc "The protected schema of an object type in a policy, or nil."
  @spec object_of(Policy.t(), atom()) :: Object.t() | nil
  def object_of(policy, type) when is_atom(policy) and is_atom(type) do
    Enum.find(Policy.objects(policy), &(Schema.object_type_of(&1.schema) == type))
  end

  @doc "A protected schema and its clauses; the schema must declare an object type."
  @spec object(module(), [Clause.t()]) :: Object.t()
  def object(schema, clauses) when is_atom(schema) and is_list(clauses) do
    if !Schema.object_type_of(schema) do
      raise ArgumentError, "object #{inspect(schema)}: the schema declares no object type"
    end

    %Object{schema: schema, clauses: clauses}
  end

  @doc "A grant clause; the source must declare a relationship whose role column the clause can name."
  @spec grant(atom(), module(), keyword()) :: Clause.t()
  def grant(name, source, options) when is_atom(name) and is_atom(source) and is_list(options) do
    validated = NimbleOptions.validate!(options, @grant_schema)

    role_column!(name, Schema.relationship_of(source), validated)

    %Clause{
      name: name,
      kind: :grant,
      source: source,
      on: validated[:on],
      role: validated[:role],
      as: validated[:as],
      through: validated[:through]
    }
  end

  @doc "A predicate clause; the function must be a capture of a named function."
  @spec predicate(atom(), Clause.predicate(), keyword()) :: Clause.t()
  def predicate(name, fun, options) when is_atom(name) and is_function(fun, 2) and is_list(options) do
    validated = NimbleOptions.validate!(options, @predicate_schema)

    if named?(fun) do
      %Clause{name: name, kind: :predicate, predicate: fun, only: validated[:only]}
    else
      raise ArgumentError, "predicate #{inspect(name)}: must be a capture of a named function"
    end
  end

  @doc "One hop of a grant's `through:` list, as `NimbleOptions` validates it."
  @spec hop(term()) :: {:ok, Clause.hop()} | {:error, String.t()}
  def hop({schema, column}) when is_atom(schema) and is_atom(column), do: {:ok, {schema, column, []}}

  def hop({schema, column, where: fun}) when is_atom(schema) and is_atom(column) and is_function(fun, 0) do
    if named?(fun) do
      {:ok, {schema, column, where: fun}}
    else
      {:error, "hop #{inspect(schema)}: where: must be a capture of a named function of no arguments"}
    end
  end

  def hop(other), do: {:error, "expected {schema, column} or {schema, column, where: fun}, got #{inspect(other)}"}

  defp named?(fun), do: match?({:type, :external}, Function.info(fun, :type))

  defp role_column!(name, nil, _validated) do
    raise ArgumentError, "grant #{inspect(name)}: the source declares no relationship"
  end

  defp role_column!(_name, %Relationship{attributes: [_role]}, _validated), do: :ok

  defp role_column!(name, %Relationship{attributes: attributes}, validated) do
    if validated[:role] || validated[:as] do
      :ok
    else
      raise ArgumentError,
            "grant #{inspect(name)}: the relationship declares #{length(attributes)} attributes; " <>
              "name the role column with role:, or a fixed role with as:"
    end
  end
end
