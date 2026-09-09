defmodule Turnstile.Schema.Fact do
  @moduledoc """
  One declared fact column: its kind, the column that names the subject, the
  column that names the object, and the element type of a set-valued column.
  Recorded by `Turnstile.Schema.fact/2` and read by the seam and the ledger.
  """

  @enforce_keys [:column, :kind, :subject, :object, :element]
  defstruct @enforce_keys

  @type kind :: :subject_attribute | :object_attribute | :relationship

  @type t :: %__MODULE__{
          column: atom(),
          kind: kind(),
          subject: atom() | nil,
          object: atom() | nil,
          element: atom() | nil
        }
end

defmodule Turnstile.Schema.Relationship do
  @moduledoc """
  A row that is a grant: the subject column, the object column, and the
  columns that are attributes of the relationship. Recorded by
  `Turnstile.Schema.relationship/1`.
  """

  @enforce_keys [:subject, :object, :attributes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{subject: atom(), object: atom(), attributes: [atom()]}
end

defmodule Turnstile.Schema do
  @moduledoc """
  Declarations on an Ecto schema: the object type it protects, the
  associations its decision covers, and the fact mapping column by column.
  Each macro records its declaration and does nothing else; the seam and the
  ledger read them back through `__turnstile__/1`.

      defmodule Example.Marking do
        use Ecto.Schema
        use Turnstile.Schema

        object_type :marking
        carries [:portions]
        fact :controls, kind: :object_attribute, object: :document_id, element: :control
        relationship subject: :user_id, object: :program_id, attributes: [:role]
      end

  `__turnstile__(:object_type)` is the declared type or `nil`;
  `__turnstile__(:carries)` the carried association names;
  `__turnstile__(:facts)` the `Turnstile.Schema.Fact` records in declaration
  order; `__turnstile__(:relationship)` the `Turnstile.Schema.Relationship`
  or `nil`. Every structure this file needs is defined in this file, so a
  schema's compile-time dependency on it reaches nothing else.
  """

  alias Turnstile.Schema.Fact
  alias Turnstile.Schema.Relationship

  @fact_schema NimbleOptions.new!(
                 kind: [type: {:in, [:subject_attribute, :object_attribute, :relationship]}, required: true],
                 subject: [
                   type: :atom,
                   doc: "The column naming the subject; a set-valued column's subject is its element."
                 ],
                 object: [type: :atom, doc: "The column naming the object."],
                 element: [
                   type: :atom,
                   doc: "The element type of a set-valued column, which is the type each element is referenced by."
                 ]
               )

  @relationship_schema NimbleOptions.new!(
                         subject: [type: :atom, required: true],
                         object: [type: :atom, required: true],
                         attributes: [type: {:list, :atom}, default: []]
                       )

  @doc false
  defmacro __using__(_opts) do
    quote do
      import Turnstile.Schema, only: [object_type: 1, carries: 1, fact: 2, relationship: 1]

      Module.register_attribute(__MODULE__, :turnstile_facts, accumulate: true)
      Module.put_attribute(__MODULE__, :turnstile_object_type, nil)
      Module.put_attribute(__MODULE__, :turnstile_carries, [])
      Module.put_attribute(__MODULE__, :turnstile_relationship, nil)
      @before_compile Turnstile.Schema
    end
  end

  @doc "Declare the object type this schema's rows are, so a query over it needs a decision."
  defmacro object_type(type) do
    quote bind_quoted: [type: type] do
      Turnstile.Schema.__declare_object_type__(__MODULE__, type)
    end
  end

  @doc "Declare the associations the parent's decision covers."
  defmacro carries(associations) do
    quote bind_quoted: [associations: associations] do
      Turnstile.Schema.__declare_carries__(__MODULE__, associations)
    end
  end

  @doc "Declare one fact column and how it maps to a fact kind."
  defmacro fact(column, options) do
    quote bind_quoted: [column: column, options: options] do
      Turnstile.Schema.__declare_fact__(__MODULE__, column, options)
    end
  end

  @doc "Declare that a row of this schema is a relationship grant."
  defmacro relationship(options) do
    quote bind_quoted: [options: options] do
      Turnstile.Schema.__declare_relationship__(__MODULE__, options)
    end
  end

  @doc false
  defmacro __before_compile__(env) do
    facts = Enum.reverse(Module.get_attribute(env.module, :turnstile_facts))

    quote do
      @doc false
      @spec __turnstile__(:object_type | :carries | :facts | :relationship) :: term()
      def __turnstile__(:object_type), do: @turnstile_object_type
      def __turnstile__(:carries), do: @turnstile_carries
      def __turnstile__(:facts), do: unquote(Macro.escape(facts))
      def __turnstile__(:relationship), do: @turnstile_relationship
    end
  end

  @doc "The object type a module declares, or `nil` for a module that declares none or is not a schema."
  @spec object_type_of(term()) :: atom() | nil
  def object_type_of(module) do
    if declares?(module), do: module.__turnstile__(:object_type)
  end

  @doc "The associations a module's decision covers; `[]` where it declares none."
  @spec carries_of(term()) :: [atom()]
  def carries_of(module) do
    if declares?(module), do: module.__turnstile__(:carries), else: []
  end

  @doc "The fact columns a module declares, in declaration order; `[]` where it declares none."
  @spec facts_of(term()) :: [Fact.t()]
  def facts_of(module) do
    if declares?(module), do: module.__turnstile__(:facts), else: []
  end

  @doc "The relationship a module's rows are, or `nil`."
  @spec relationship_of(term()) :: Relationship.t() | nil
  def relationship_of(module) do
    if declares?(module), do: module.__turnstile__(:relationship)
  end

  @doc "Whether a module carries fact declarations: a fact column or a relationship."
  @spec fact_schema?(term()) :: boolean()
  def fact_schema?(module), do: facts_of(module) != [] or relationship_of(module) != nil

  @doc "Whether a module used `Turnstile.Schema`."
  @spec declares?(term()) :: boolean()
  def declares?(module) when is_atom(module) and not is_nil(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :__turnstile__, 1)
  end

  def declares?(_other), do: false

  @doc false
  @spec __declare_object_type__(module(), atom()) :: :ok
  def __declare_object_type__(module, type) when is_atom(module) and is_atom(type) and not is_nil(type) do
    case Module.get_attribute(module, :turnstile_object_type) do
      nil -> Module.put_attribute(module, :turnstile_object_type, type)
      other -> raise ArgumentError, "#{inspect(module)} already declares object_type #{inspect(other)}"
    end
  end

  @doc false
  @spec __declare_carries__(module(), [atom()]) :: :ok
  def __declare_carries__(module, associations) when is_atom(module) and is_list(associations) do
    if !Enum.all?(associations, &is_atom/1) do
      raise ArgumentError, "carries expects a list of association names, got: #{inspect(associations)}"
    end

    declared = Module.get_attribute(module, :turnstile_carries)

    case Enum.filter(associations, &(&1 in declared)) do
      [] -> Module.put_attribute(module, :turnstile_carries, declared ++ associations)
      repeated -> raise ArgumentError, "#{inspect(module)} already carries #{inspect(repeated)}"
    end
  end

  @doc false
  @spec __declare_fact__(module(), atom(), keyword()) :: :ok
  def __declare_fact__(module, column, options) when is_atom(module) and is_atom(column) and is_list(options) do
    options = NimbleOptions.validate!(options, @fact_schema)

    fact = %Fact{
      column: column,
      kind: options[:kind],
      subject: options[:subject],
      object: options[:object],
      element: options[:element]
    }

    Module.put_attribute(module, :turnstile_facts, fact)
  end

  @doc false
  @spec __declare_relationship__(module(), keyword()) :: :ok
  def __declare_relationship__(module, options) when is_atom(module) and is_list(options) do
    options = NimbleOptions.validate!(options, @relationship_schema)

    case Module.get_attribute(module, :turnstile_relationship) do
      nil ->
        relationship = %Relationship{
          subject: options[:subject],
          object: options[:object],
          attributes: options[:attributes]
        }

        Module.put_attribute(module, :turnstile_relationship, relationship)

      %Relationship{} ->
        raise ArgumentError, "#{inspect(module)} already declares a relationship"
    end
  end
end
