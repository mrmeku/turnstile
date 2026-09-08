defmodule Turnstile.Code.Policy.Role do
  @moduledoc "One row of the role table: a role and the operations it permits."

  @enforce_keys [:name, :permissions]
  defstruct @enforce_keys

  @type t :: %__MODULE__{name: atom(), permissions: [atom()]}
end

defmodule Turnstile.Code.Policy.Clause do
  @moduledoc """
  One clause of a protected schema's rule. A grant names a relationship
  schema whose rows hold a role for the subject on the object: `on` is the
  column of the protected schema the relationship's object column names,
  `role` the relationship column that holds the role, and `as` a role every
  row holds when the relationship has no role column. `through` is the
  chain of hops a grant crosses when the relationship names a row that is
  not the protected one: each hop is a schema, the column of it the inner
  set matches, and an optional `where:` capture of a named function of no
  arguments returning a `dynamic` over the hop's row; the hop's primary key
  is what the next hop, or the protected row's `on` column, is matched
  against. A predicate is a function of the subject and the environment
  returning a `dynamic` over the protected row, or a boolean; `only` names
  the operations it applies to, every operation when nil.
  """

  alias Turnstile.Environment
  alias Turnstile.Subject

  @enforce_keys [:name, :kind]
  defstruct [:name, :kind, source: nil, on: nil, role: nil, as: nil, through: [], predicate: nil, only: nil]

  @type kind :: :grant | :predicate
  @type predicate :: (Subject.t(), Environment.t() -> Ecto.Query.dynamic_expr() | boolean())
  @type hop :: {module(), atom(), [where: (-> Ecto.Query.dynamic_expr())]}

  @type t :: %__MODULE__{
          name: atom(),
          kind: kind(),
          source: module() | nil,
          on: atom() | nil,
          role: atom() | nil,
          as: atom() | nil,
          through: [hop()],
          predicate: predicate() | nil,
          only: [atom()] | nil
        }
end

defmodule Turnstile.Code.Policy.Object do
  @moduledoc "A protected schema and the clauses of its rule."

  alias Turnstile.Code.Policy.Clause

  @enforce_keys [:schema, :clauses]
  defstruct @enforce_keys

  @type t :: %__MODULE__{schema: module(), clauses: [Clause.t()]}
end

defmodule Turnstile.Code.Policy do
  @moduledoc """
  The policy module: the role table as data and, per protected schema, the
  clauses of its rule.

      defmodule MyApp.Roles do
        use Turnstile.Code.Policy, version: "2026.09.1", author: "platform", approval: "ticket 41"

        role :reader, [:read]
        role :editor, [:read, :edit]

        object MyApp.Folder do
          grant :membership, MyApp.Membership
          predicate :cleared, &MyApp.Predicates.cleared/2
        end
      end

  An operation is allowed on a row when any grant holds a role that permits
  it and every predicate that applies to the operation holds. A grant's
  relationship schema declares its subject, object, and role columns with
  `Turnstile.Schema.relationship/1`; the grant reads them, and takes `on:`,
  `role:`, or `as:` when the schema's declaration is not enough. When the
  relationship names a row the protected row points at rather than the
  protected row itself, `through:` lists the hops from the protected row
  outward, each a schema and the column of it the inner set matches, with
  an optional `where:` capture that narrows the hop's rows:

      object MyApp.Page do
        grant :membership, MyApp.Membership, on: :folder_id, through: [{MyApp.Folder, :id, where: &MyApp.Rules.open/0}]
      end

  A predicate is a capture of a named function, so the policy stays data a
  hash can name; `only:` names the operations it applies to. `version:`
  defaults to the content hash of the policy's modules, `author:` and
  `approval:` to `"unrecorded"`.
  """

  alias Turnstile.Code.Policy.Clause
  alias Turnstile.Code.Policy.Object
  alias Turnstile.Code.Policy.Role
  alias Turnstile.Schema
  alias Turnstile.Schema.Relationship

  @use_schema NimbleOptions.new!(
                version: [type: {:or, [:string, nil]}, default: nil, doc: "The version identifier a decision names."],
                author: [type: :string, default: "unrecorded", doc: "Who wrote the version."],
                approval: [type: :string, default: "unrecorded", doc: "Who approved it, or where."]
              )

  @grant_schema NimbleOptions.new!(
                  on: [type: :atom, doc: "The protected column the relationship's object column names."],
                  role: [type: :atom, doc: "The relationship column that holds the role."],
                  as: [type: :atom, doc: "The role every row holds, when there is no role column."],
                  through: [
                    type: {:list, {:custom, __MODULE__, :__hop__, []}},
                    default: [],
                    doc:
                      "The hops from the protected row outward, each `{schema, column}` or `{schema, column, where: fun}`."
                  ]
                )

  @predicate_schema NimbleOptions.new!(
                      only: [type: {:list, :atom}, doc: "The operations the predicate applies to; all when absent."]
                    )

  @type t :: module()

  @doc "The options `use` accepts."
  @spec use_schema() :: NimbleOptions.t()
  def use_schema, do: @use_schema

  @doc "The options `grant` accepts."
  @spec grant_schema() :: NimbleOptions.t()
  def grant_schema, do: @grant_schema

  @doc "The options `predicate` accepts."
  @spec predicate_schema() :: NimbleOptions.t()
  def predicate_schema, do: @predicate_schema

  defmacro __using__(options) do
    quote bind_quoted: [options: options] do
      import Turnstile.Code.Policy, only: [role: 2, object: 2, grant: 2, grant: 3, predicate: 2, predicate: 3]

      alias Turnstile.Code.Policy

      @turnstile_code_options NimbleOptions.validate!(options, Policy.use_schema())
      Module.register_attribute(__MODULE__, :turnstile_code_roles, accumulate: true)
      Module.register_attribute(__MODULE__, :turnstile_code_objects, accumulate: true)
      @before_compile Policy
    end
  end

  @doc "A row of the role table."
  defmacro role(name, permissions) do
    quote bind_quoted: [name: name, permissions: permissions] do
      @turnstile_code_roles Turnstile.Code.Policy.__role__(name, permissions)
    end
  end

  @doc "A protected schema and, in the block, the clauses of its rule."
  defmacro object(schema, do: block) do
    quote do
      @turnstile_code_clauses []
      unquote(block)
      @turnstile_code_objects Turnstile.Code.Policy.__object__(unquote(schema), @turnstile_code_clauses)
    end
  end

  @doc "A grant clause: the relationship schema whose rows hold a role on the protected row."
  defmacro grant(name, source, options \\ []) do
    quote bind_quoted: [name: name, source: source, options: options] do
      @turnstile_code_clauses [Turnstile.Code.Policy.__grant__(name, source, options) | @turnstile_code_clauses]
    end
  end

  @doc "A predicate clause: a capture of a named function of the subject and the environment."
  defmacro predicate(name, fun, options \\ []) do
    quote bind_quoted: [name: name, fun: fun, options: options] do
      @turnstile_code_clauses [Turnstile.Code.Policy.__predicate__(name, fun, options) | @turnstile_code_clauses]
    end
  end

  defmacro __before_compile__(_env) do
    quote do
      @doc false
      @spec __turnstile_code__(:roles | :objects | :options) :: term()
      def __turnstile_code__(:roles), do: Enum.reverse(@turnstile_code_roles)

      def __turnstile_code__(:objects), do: unquote(__MODULE__.__objects__(__CALLER__.module))

      def __turnstile_code__(:options), do: @turnstile_code_options
    end
  end

  @doc "The role table."
  @spec roles(t()) :: [Role.t()]
  def roles(policy) when is_atom(policy), do: policy.__turnstile_code__(:roles)

  @doc "The protected schemas and their clauses."
  @spec objects(t()) :: [Object.t()]
  def objects(policy) when is_atom(policy), do: policy.__turnstile_code__(:objects)

  @doc "The protected schema of an object type, or nil."
  @spec object_of(t(), atom()) :: Object.t() | nil
  def object_of(policy, type) when is_atom(policy) and is_atom(type) do
    Enum.find(objects(policy), &(Schema.object_type_of(&1.schema) == type))
  end

  @doc "Every operation some role permits."
  @spec operations(t()) :: [atom()]
  def operations(policy) when is_atom(policy) do
    policy
    |> roles()
    |> Enum.flat_map(& &1.permissions)
    |> Enum.uniq()
  end

  @doc "The roles that permit an operation."
  @spec roles_for(t(), atom()) :: [atom()]
  def roles_for(policy, operation) when is_atom(policy) and is_atom(operation) do
    for %Role{name: name, permissions: permissions} <- roles(policy), operation in permissions, do: name
  end

  @doc "The role table as data: each role's name to its permissions."
  @spec table(t()) :: keyword([atom()])
  def table(policy) when is_atom(policy) do
    for %Role{name: name, permissions: permissions} <- roles(policy), do: {name, permissions}
  end

  @doc "The modules the rules live in: the policy and the module of every predicate and hop filter, sorted."
  @spec modules(t()) :: [module()]
  def modules(policy) when is_atom(policy) do
    clauses = for %Object{clauses: clauses} <- objects(policy), clause <- clauses, do: clause
    predicates = for %Clause{kind: :predicate, predicate: fun} <- clauses, do: module_of(fun)
    filters = for %Clause{through: hops} <- clauses, {_schema, _column, where: fun} <- hops, do: module_of(fun)

    Enum.sort(Enum.uniq([policy | predicates ++ filters]))
  end

  @doc "The `use` options: version, author, approval."
  @spec options(t()) :: keyword()
  def options(policy) when is_atom(policy), do: policy.__turnstile_code__(:options)

  @doc false
  @spec __objects__(module()) :: Macro.t()
  def __objects__(module) when is_atom(module) do
    module
    |> Module.get_attribute(:turnstile_code_objects)
    |> Enum.reverse()
    |> Macro.escape()
  end

  @doc false
  @spec __role__(atom(), [atom()]) :: Role.t()
  def __role__(name, permissions) when is_atom(name) and is_list(permissions) do
    if !Enum.all?(permissions, &is_atom/1) do
      raise ArgumentError, "role #{inspect(name)}: permissions must be atoms, got #{inspect(permissions)}"
    end

    %Role{name: name, permissions: permissions}
  end

  @doc false
  @spec __object__(module(), [Clause.t()]) :: Object.t()
  def __object__(schema, clauses) when is_atom(schema) and is_list(clauses) do
    if !Schema.object_type_of(schema) do
      raise ArgumentError, "object #{inspect(schema)}: the schema declares no object type"
    end

    %Object{schema: schema, clauses: Enum.reverse(clauses)}
  end

  @doc false
  @spec __grant__(atom(), module(), keyword()) :: Clause.t()
  def __grant__(name, source, options) when is_atom(name) and is_atom(source) and is_list(options) do
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

  @doc false
  @spec __predicate__(atom(), Clause.predicate(), keyword()) :: Clause.t()
  def __predicate__(name, fun, options) when is_atom(name) and is_function(fun, 2) and is_list(options) do
    validated = NimbleOptions.validate!(options, @predicate_schema)

    if named?(fun) do
      %Clause{name: name, kind: :predicate, predicate: fun, only: validated[:only]}
    else
      raise ArgumentError, "predicate #{inspect(name)}: must be a capture of a named function"
    end
  end

  @doc false
  @spec __hop__(term()) :: {:ok, Clause.hop()} | {:error, String.t()}
  def __hop__({schema, column}) when is_atom(schema) and is_atom(column), do: {:ok, {schema, column, []}}

  def __hop__({schema, column, where: fun}) when is_atom(schema) and is_atom(column) and is_function(fun, 0) do
    if named?(fun) do
      {:ok, {schema, column, where: fun}}
    else
      {:error, "hop #{inspect(schema)}: where: must be a capture of a named function of no arguments"}
    end
  end

  def __hop__(other), do: {:error, "expected {schema, column} or {schema, column, where: fun}, got #{inspect(other)}"}

  defp named?(fun), do: match?({:type, :external}, Function.info(fun, :type))

  defp module_of(fun), do: elem(Function.info(fun, :module), 1)

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
