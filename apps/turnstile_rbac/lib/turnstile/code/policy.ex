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

  The role table is data at compile time. The clauses are built when the
  policy is read, by `Turnstile.Code.Policy.Clauses`, which checks each
  against the schemas it names; a policy that names a schema without an
  object type, a relationship the grant cannot read, or a predicate that is
  not a named capture raises there, so a bad policy fails at boot, when
  `Turnstile.Code.publish/0` reads it, and not on a request. Building at
  read time keeps the policy module free of compile-time dependencies on
  the schemas and predicates it names: a change to any of them recompiles
  nothing but itself.
  """

  alias Turnstile.Code.Policy.Clauses
  alias Turnstile.Code.Policy.Object
  alias Turnstile.Code.Policy.Role

  @use_schema NimbleOptions.new!(
                version: [type: {:or, [:string, nil]}, default: nil, doc: "The version identifier a decision names."],
                author: [type: :string, default: "unrecorded", doc: "Who wrote the version."],
                approval: [type: :string, default: "unrecorded", doc: "Who approved it, or where."]
              )

  @type t :: module()

  @doc "The options `use` accepts."
  @spec use_schema() :: NimbleOptions.t()
  def use_schema, do: @use_schema

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
      @turnstile_code_objects {unquote(expanded(schema, __CALLER__)), Enum.reverse(@turnstile_code_clauses)}
    end
  end

  @doc "A grant clause: the relationship schema whose rows hold a role on the protected row."
  defmacro grant(name, source, options \\ []) do
    clause =
      quote do
        Clauses.grant(
          unquote(name),
          unquote(expanded(source, __CALLER__)),
          unquote(expanded(options, __CALLER__))
        )
      end

    quote do
      @turnstile_code_clauses [unquote(Macro.escape(clause)) | @turnstile_code_clauses]
    end
  end

  @doc "A predicate clause: a capture of a named function of the subject and the environment."
  defmacro predicate(name, fun, options \\ []) do
    clause =
      quote do
        Clauses.predicate(
          unquote(name),
          unquote(expanded(fun, __CALLER__)),
          unquote(expanded(options, __CALLER__))
        )
      end

    quote do
      @turnstile_code_clauses [unquote(Macro.escape(clause)) | @turnstile_code_clauses]
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

  @doc "The protected schemas and their clauses, built and checked against the schemas they name."
  @spec objects(t()) :: [Object.t()]
  def objects(policy) when is_atom(policy), do: policy.__turnstile_code__(:objects)

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
    predicates = for %{kind: :predicate, predicate: fun} <- clauses, do: module_of(fun)
    filters = for %{through: hops} <- clauses, {_schema, _column, where: fun} <- hops, do: module_of(fun)

    Enum.sort(Enum.uniq([policy | predicates ++ filters]))
  end

  @doc "The `use` options: version, author, approval."
  @spec options(t()) :: keyword()
  def options(policy) when is_atom(policy), do: policy.__turnstile_code__(:options)

  @doc false
  @spec __objects__(module()) :: Macro.t()
  def __objects__(module) when is_atom(module) do
    objects = Enum.reverse(Module.get_attribute(module, :turnstile_code_objects))

    for {schema, clauses} <- objects do
      quote do
        Clauses.object(unquote(schema), unquote(clauses))
      end
    end
  end

  @doc false
  @spec __role__(atom(), [atom()]) :: Role.t()
  def __role__(name, permissions) when is_atom(name) and is_list(permissions) do
    if !Enum.all?(permissions, &is_atom/1) do
      raise ArgumentError, "role #{inspect(name)}: permissions must be atoms, got #{inspect(permissions)}"
    end

    %Role{name: name, permissions: permissions}
  end

  defp module_of(fun), do: elem(Function.info(fun, :module), 1)

  # The caller's aliases resolved where the policy names a module, so the
  # clause reads the same when the generated function is compiled. The
  # expansion runs under a function environment: an alias expanded in a
  # module body is a compile-time dependency, and the policy must not
  # recompile when a schema or a predicate module changes.
  defp expanded(ast, env) do
    inside = %{env | function: {:__turnstile_code__, 1}}

    Macro.prewalk(ast, fn
      {:__aliases__, _meta, _parts} = alias -> Macro.expand(alias, inside)
      other -> other
    end)
  end
end
