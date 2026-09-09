defmodule Turnstile.Postgres.Binding do
  @moduledoc """
  What `Turnstile.Postgres` needs beyond the configuration: the mediated
  repo whose connection carries the session settings, the schemas whose
  tables the policies protect and read, and the name of the table that
  holds the migration numbers. `bind/1` validates them and keeps them for
  the life of the VM, as `Turnstile.Config.boot!/1` keeps the
  configuration; `override/1` puts a binding in the calling process for the
  rest of its life, read from the caller and from its `$callers` chain, so
  a test binds its own repo without touching the boot binding.

  The schemas serve three lookups: an object type to the table and primary
  key its answers run against, a table back to the schema whose
  declarations cover it, and the set of tables whose policies are the
  adapter's business.
  """

  alias Turnstile.Error
  alias Turnstile.Schema

  @schema NimbleOptions.new!(
            repo: [type: :atom, required: true, doc: "The mediated repo the settings and the answers run through."],
            schemas: [
              type: {:list, :atom},
              required: true,
              doc: "The schemas that used `Turnstile.Schema`, whose tables the policies protect and read."
            ],
            migrations_table: [
              type: :string,
              default: "schema_migrations",
              doc: "The table whose highest version is the policy version."
            ]
          )

  @enforce_keys [:repo, :schemas, :migrations_table]
  defstruct @enforce_keys

  @type t :: %__MODULE__{repo: module(), schemas: [module()], migrations_table: String.t()}

  @doc "The schema of the binding's options."
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "Validate the options into the struct."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def new(options) when is_list(options) do
    with {:ok, validated} <- validate(options),
         :ok <- declared?(validated[:schemas]) do
      {:ok,
       %__MODULE__{
         repo: validated[:repo],
         schemas: validated[:schemas],
         migrations_table: validated[:migrations_table]
       }}
    end
  end

  @doc "Validate once at boot and keep the binding for `resolve/0`."
  @spec bind(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def bind(options) when is_list(options) do
    with {:ok, %__MODULE__{} = binding} <- new(options) do
      :persistent_term.put(__MODULE__, binding)
      {:ok, binding}
    end
  end

  @doc "`bind/1`, raising the error."
  @spec bind!(keyword()) :: t()
  def bind!(options) when is_list(options) do
    case bind(options) do
      {:ok, binding} -> binding
      {:error, error} -> raise error
    end
  end

  @doc "Override the binding's fields for the rest of the calling process."
  @spec override(keyword()) :: :ok
  def override(overrides) when is_list(overrides) do
    current = Process.get(__MODULE__, [])
    Process.put(__MODULE__, Keyword.merge(current, overrides))
    :ok
  end

  @doc "Override the binding's fields around a function, restoring the previous override after it."
  @spec override(keyword(), (-> result)) :: result when result: term()
  def override(overrides, fun) when is_list(overrides) and is_function(fun, 0) do
    previous = Process.get(__MODULE__, [])
    :ok = override(overrides)

    try do
      fun.()
    after
      Process.put(__MODULE__, previous)
    end
  end

  @doc "The boot binding under the calling process's overrides, or an error when neither exists."
  @spec resolve() :: {:ok, t()} | {:error, Error.Invalid.t()}
  def resolve do
    overrides = overrides()

    case :persistent_term.get(__MODULE__, nil) do
      %__MODULE__{} = base -> new(Keyword.merge(to_keyword(base), overrides))
      nil when overrides == [] -> {:error, invalid("nothing bound and no override")}
      nil -> new(overrides)
    end
  end

  @doc "The binding as the keyword list `new/1` accepts."
  @spec to_keyword(t()) :: keyword()
  def to_keyword(%__MODULE__{} = binding) do
    [repo: binding.repo, schemas: binding.schemas, migrations_table: binding.migrations_table]
  end

  @doc "The tables of the bound schemas, sorted."
  @spec tables(t()) :: [String.t()]
  def tables(%__MODULE__{schemas: schemas}) do
    schemas
    |> Enum.map(& &1.__schema__(:source))
    |> Enum.sort()
  end

  @doc "The schema, table, and single primary key of an object type, or `nil` when no bound schema has one."
  @spec target(t(), atom()) :: {module(), String.t(), atom()} | nil
  def target(%__MODULE__{schemas: schemas}, object_type) when is_atom(object_type) do
    Enum.find_value(schemas, fn schema ->
      if Schema.object_type_of(schema) == object_type, do: single_key(schema)
    end)
  end

  @doc "The bound schema whose table is `table`, or `nil`."
  @spec schema_of(t(), String.t()) :: module() | nil
  def schema_of(%__MODULE__{schemas: schemas}, table) when is_binary(table) do
    Enum.find(schemas, &(&1.__schema__(:source) == table))
  end

  # A type whose key is not one column has no target: an answer names a row
  # by a single primary key or not at all.
  defp single_key(schema) do
    case schema.__schema__(:primary_key) do
      [column] -> {schema, schema.__schema__(:source), column}
      _composite_or_none -> nil
    end
  end

  defp validate(options) do
    case NimbleOptions.validate(options, @schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, invalid(Exception.message(error))}
    end
  end

  defp declared?(schemas) do
    case Enum.reject(schemas, &Schema.declares?/1) do
      [] -> :ok
      undeclared -> {:error, invalid("#{Enum.map_join(undeclared, ", ", &inspect/1)} did not use Turnstile.Schema")}
    end
  end

  defp invalid(detail), do: %Error.Invalid{what: :binding, detail: detail}

  # The override is read from the calling process, then from each process in
  # its `$callers` chain, nearest first; the first one found wins.
  defp overrides do
    [self() | List.wrap(Process.get(:"$callers", []))]
    |> Enum.map(&overrides_of/1)
    |> Enum.find([], &(&1 != []))
  end

  defp overrides_of(pid) when pid == self(), do: Process.get(__MODULE__, [])

  defp overrides_of(pid) do
    case Process.info(pid, :dictionary) do
      {:dictionary, dictionary} -> Keyword.get(dictionary, __MODULE__, [])
      nil -> []
    end
  end
end
