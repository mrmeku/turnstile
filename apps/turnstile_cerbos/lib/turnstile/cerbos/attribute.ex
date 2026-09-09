defmodule Turnstile.Cerbos.Attribute do
  @moduledoc """
  One attribute declaration: the name the policies know it by, and where its
  value comes from.

  Two sources. `column:` names a column of the kind's schema, so the value
  is what the row holds. `subquery:` names a function of the subject that
  returns a query selecting `%{id: ..., value: ...}` with the value as
  text, since text is what a policy compares against; the value then
  depends on who is asking: the ids are the rows the values belong to, and
  a row with several values gets the list of them. A subject's own
  attribute declared this way gets the list of its values, since its id is
  the only one asked about.

  The name `environment` is not one a declaration may take: it is the
  principal attribute the request-time facts travel under, so a declaration
  of that name would put a row's value where the moment of the request
  goes.

  The two sources differ in what a query plan can be compiled to. A column
  becomes a comparison on the row. A subquery becomes membership in the
  ids the subquery selects, which is why a rule that tests a subject's
  reach over rows can still be answered as one query rather than a list of
  ids.
  """

  alias Turnstile.Error

  @schema NimbleOptions.new!(
            column: [type: :atom, doc: "The column of the kind's schema the value is read from."],
            subquery: [
              type: {:fun, 1},
              doc: "A function of the subject returning a query selecting `%{id: ..., value: ...}`, the value as text."
            ]
          )

  @reserved :environment

  @enforce_keys [:name, :source]
  defstruct [:name, :source]

  @typedoc "Where an attribute's value comes from."
  @type source :: {:column, atom()} | {:subquery, (Turnstile.Subject.t() -> Ecto.Queryable.t())}

  @type t :: %__MODULE__{name: atom(), source: source()}

  @doc "The attribute name the request-time facts travel under, which no declaration may take."
  @spec reserved() :: atom()
  def reserved, do: @reserved

  @doc "The schema of an attribute declaration's options."
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "The declaration, or the reason it is not one."
  @spec new(atom(), keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def new(name, options) when is_atom(name) and is_list(options) do
    with :ok <- available(name),
         {:ok, validated} <- validate(name, options),
         {:ok, source} <- source(name, validated) do
      {:ok, %__MODULE__{name: name, source: source}}
    end
  end

  @doc "`new/2`, raising the error, which is what a declaration in a module does."
  @spec new!(atom(), keyword()) :: t()
  def new!(name, options) when is_atom(name) and is_list(options) do
    case new(name, options) do
      {:ok, attribute} -> attribute
      {:error, error} -> raise error
    end
  end

  @doc "Whether the attribute reads a column of the row."
  @spec column?(t()) :: boolean()
  def column?(%__MODULE__{source: {:column, _column}}), do: true
  def column?(%__MODULE__{}), do: false

  defp available(@reserved), do: {:error, invalid(@reserved, "is the name the request-time facts travel under")}
  defp available(_name), do: :ok

  defp validate(name, options) do
    case NimbleOptions.validate(options, @schema) do
      {:ok, validated} -> {:ok, validated}
      {:error, %NimbleOptions.ValidationError{} = error} -> {:error, invalid(name, Exception.message(error))}
    end
  end

  defp source(name, validated) do
    case {validated[:column], validated[:subquery]} do
      {column, nil} when is_atom(column) and not is_nil(column) -> {:ok, {:column, column}}
      {nil, subquery} when is_function(subquery, 1) -> {:ok, {:subquery, subquery}}
      {nil, nil} -> {:error, invalid(name, "names neither a column nor a subquery")}
      {_column, _subquery} -> {:error, invalid(name, "names both a column and a subquery")}
    end
  end

  defp invalid(name, detail), do: %Error.Invalid{what: :attribute, detail: "attribute #{name} " <> detail}
end
