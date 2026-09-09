defmodule Turnstile.Cerbos.Attributes do
  @moduledoc """
  The declarations that say what the adapter may send the sidecar and what
  a query plan may be compiled over.

      defmodule MyApp.Attributes do
        use Turnstile.Cerbos.Attributes

        principal :user, schema: MyApp.Person do
          attribute :nationality, column: :nationality
        end

        resource :document, schema: MyApp.Document do
          attribute :effective_controls, subquery: &MyApp.Markings.effective_controls_for/1
        end

        environment do
          fact :reauthenticated_at
        end
      end

  A `principal` block names a subject kind and the schema whose row is the
  subject; a `resource` block names an object type and the schema whose rows
  are the objects. Inside either, `attribute/2` maps a name the policies use
  to a column or to a subquery (`Turnstile.Cerbos.Attribute`).

  An `environment` block names the request-time facts a policy may read.
  They come from the caller rather than from a row, and they reach the
  policies as the principal attribute `Turnstile.Cerbos.Attribute.reserved/0`
  beside the moment the port stamped the request with, which travels
  whether anything is declared or not
  (`Turnstile.Cerbos.Values.environment/2`). A fact the caller did not
  supply goes as nothing rather than being left out.

  Two rules follow from the declarations, and they are the reason the
  declarations exist rather than the adapter sending whatever it finds.
  The adapter sends the sidecar the declared attributes and the declared
  request-time facts and nothing else, so a policy cannot come to depend on
  a value no one declared. And the query plan the sidecar returns is
  compiled over declared attributes alone, so a plan that reads anything
  else is a plan this adapter refuses to turn into a query. What the columns
  behind them must also be is a declared fact of the application, which
  `Turnstile.Cerbos.Coverage` checks.

  A module that used this one answers `__turnstile_cerbos__/1`, and the
  functions here read the declarations through it, so what a declaration
  module carries is the declarations and nothing more.
  """

  alias Turnstile.Cerbos.Attribute

  @kind_schema NimbleOptions.new!(
                 schema: [
                   type: :atom,
                   required: true,
                   doc: "The Ecto schema whose rows the kind's attributes are read from."
                 ]
               )

  @typedoc "A module that used this one."
  @type t :: module()

  @typedoc "A declared kind: the side it is on, its name, and the schema behind it."
  @type kind :: {:principal | :resource, atom(), module()}

  @doc false
  defmacro __using__(_options) do
    quote do
      import Turnstile.Cerbos.Attributes, only: [attribute: 2, environment: 1, principal: 3, resource: 3]

      Module.register_attribute(__MODULE__, :turnstile_cerbos_kinds, accumulate: true)
      Module.register_attribute(__MODULE__, :turnstile_cerbos_declared, accumulate: true)
      Module.register_attribute(__MODULE__, :turnstile_cerbos_facts, accumulate: true)
      Module.put_attribute(__MODULE__, :turnstile_cerbos_current, nil)

      @before_compile Turnstile.Cerbos.Attributes
    end
  end

  @doc "Declare the attributes of a subject kind, read from the row the subject's id names."
  defmacro principal(kind, options, do: block), do: kind(:principal, kind, options, block, __CALLER__)

  @doc "Declare the attributes of an object type, read from the rows the objects name."
  defmacro resource(kind, options, do: block), do: kind(:resource, kind, options, block, __CALLER__)

  @doc """
  Declare the request-time facts the policies may read, each with
  `fact :name`, where the name is the key the caller's facts carry.
  """
  defmacro environment(do: block) do
    {:__block__, [], Enum.map(fact_names(block), &quote(do: @turnstile_cerbos_facts(unquote(&1))))}
  end

  @doc "Declare one attribute of the block it stands in: `column:` or `subquery:`."
  defmacro attribute(name, options) do
    quote do
      @turnstile_cerbos_declared {@turnstile_cerbos_current, unquote(name)}

      @doc false
      def __attribute__(@turnstile_cerbos_current, unquote(name)) do
        Attribute.new!(unquote(name), unquote(options))
      end
    end
  end

  @doc false
  defmacro __before_compile__(_env) do
    quote do
      @doc false
      @spec __turnstile_cerbos__(:kinds | :declared | :facts) :: term()
      def __turnstile_cerbos__(:kinds), do: Enum.reverse(@turnstile_cerbos_kinds)
      def __turnstile_cerbos__(:declared), do: Enum.reverse(@turnstile_cerbos_declared)
      def __turnstile_cerbos__(:facts), do: Enum.reverse(@turnstile_cerbos_facts)
    end
  end

  @doc "The schema of the options a `principal` or `resource` block takes."
  @spec kind_options_schema() :: NimbleOptions.t()
  def kind_options_schema, do: @kind_schema

  @doc "Whether the module is a declaration module of this adapter."
  @spec declares?(module()) :: boolean()
  def declares?(module) when is_atom(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__turnstile_cerbos__, 1)
  end

  @doc "The request-time facts declared, in the order they were written."
  @spec facts(t()) :: [atom()]
  def facts(module) when is_atom(module), do: module.__turnstile_cerbos__(:facts)

  @doc "The subject kinds and object types declared, with the side each is on and its schema."
  @spec kinds(t()) :: [kind()]
  def kinds(module) when is_atom(module), do: module.__turnstile_cerbos__(:kinds)

  @doc "The subject kinds declared."
  @spec principals(t()) :: [atom()]
  def principals(module) when is_atom(module), do: for({:principal, kind, _schema} <- kinds(module), do: kind)

  @doc "The object types declared."
  @spec resources(t()) :: [atom()]
  def resources(module) when is_atom(module), do: for({:resource, kind, _schema} <- kinds(module), do: kind)

  @doc "Whether the module declares the kind, on either side."
  @spec declared?(t(), atom()) :: boolean()
  def declared?(module, kind) when is_atom(module) and is_atom(kind) do
    Enum.any?(kinds(module), fn {_side, name, _schema} -> name == kind end)
  end

  @doc "The schema a kind's attributes are read from, or `nil` when the kind is not declared."
  @spec schema_of(t(), atom()) :: module() | nil
  def schema_of(module, kind) when is_atom(module) and is_atom(kind) do
    Enum.find_value(kinds(module), fn {_side, name, schema} -> if name == kind, do: schema end)
  end

  @doc "The attribute declarations of a kind, in the order they were written."
  @spec attributes_of(t(), atom()) :: [Attribute.t()]
  def attributes_of(module, kind) when is_atom(module) and is_atom(kind) do
    for {declared, name} <- module.__turnstile_cerbos__(:declared),
        declared == kind,
        do: module.__attribute__(kind, name)
  end

  @doc "Every declaration of the module, both sides, as the pairs `attributes_of/2` answers."
  @spec all(t()) :: [{atom(), Attribute.t()}]
  def all(module) when is_atom(module) do
    for {_side, kind, _schema} <- kinds(module), attribute <- attributes_of(module, kind), do: {kind, attribute}
  end

  @doc "The declaration of one attribute of one kind, or `nil`."
  @spec find(t(), atom(), atom()) :: Attribute.t() | nil
  def find(module, kind, name) when is_atom(module) and is_atom(kind) and is_atom(name) do
    Enum.find(attributes_of(module, kind), &(&1.name == name))
  end

  # The block is read where it stands rather than by a macro per fact,
  # so an expression that is not a fact declaration is refused as one.
  defp fact_names({:__block__, _meta, declarations}), do: Enum.map(declarations, &fact_name/1)
  defp fact_names(declaration), do: [fact_name(declaration)]

  defp fact_name({:fact, _meta, [name]}) when is_atom(name), do: name

  defp fact_name(other) do
    raise ArgumentError, "an environment block declares a fact with `fact :name`, not #{Macro.to_string(other)}"
  end

  defp kind(side, kind, options, block, caller) do
    quote do
      options = NimbleOptions.validate!(unquote(expanded(options, caller)), unquote(__MODULE__).kind_options_schema())
      @turnstile_cerbos_kinds {unquote(side), unquote(kind), options[:schema]}
      @turnstile_cerbos_current unquote(kind)
      unquote(block)
      @turnstile_cerbos_current nil
    end
  end

  # The declaring module's aliases resolved where a declaration names a
  # schema, under a function environment: an alias expanded in a module body
  # is a compile-time dependency, and a declaration must not recompile when
  # the schema behind it changes.
  defp expanded(ast, env) do
    inside = %{env | function: {:__turnstile_cerbos__, 1}}

    Macro.prewalk(ast, fn
      {:__aliases__, _meta, _parts} = alias -> Macro.expand(alias, inside)
      other -> other
    end)
  end
end
