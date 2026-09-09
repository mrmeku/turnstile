defmodule Turnstile.Cerbos.Plan do
  @moduledoc """
  A query plan turned into a `dynamic` over the rows of the object type.

  The sidecar answers a plan request with a filter over the resource
  attributes it could not resolve, which is what makes a list one query
  rather than a decision per row. Three shapes come back. A plan that
  admits every row becomes `true`; a plan that admits none is a denial the
  adapter answers with; a conditional plan is an expression tree over
  `request.resource.attr.<name>` and values, which this module compiles
  against the declarations: an attribute read from a column becomes a
  comparison on that column, and an attribute read from a subquery becomes
  membership in the ids the subquery selects for the asking subject.

  An expression this module cannot express is not guessed at and not
  ignored: it is an error, and the caller records the operation as limited
  and asks the port for each row instead. The reason is that a plan
  narrowed by half is a query that returns rows a policy denies, and a
  plan discarded is a list that returns nothing where the policy allows;
  the honest answer is that the query plan does not carry this rule.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2, subquery: 1]

  alias Turnstile.Cerbos.Attribute
  alias Turnstile.Cerbos.Attributes
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Subject

  @enforce_keys [:subject, :attributes, :kind, :schema, :key]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          subject: Subject.t(),
          attributes: module(),
          kind: atom(),
          schema: module(),
          key: atom()
        }

  @doc """
  The rule the filter carries: `{:ok, rule}` for a plan every row of the
  object type is measured against, `:denied` for a plan that admits no row,
  and `{:error, detail}` for a plan this adapter does not express.
  """
  @spec dynamic(Binding.t(), Subject.t(), atom(), map()) ::
          {:ok, Ecto.Query.dynamic_expr()} | :denied | {:error, String.t()}
  def dynamic(%Binding{} = binding, %Subject{} = subject, kind, filter) when is_atom(kind) and is_map(filter) do
    case Binding.target(binding, kind) do
      {schema, key} -> filtered(new(binding, subject, kind, schema, key), filter)
      nil -> {:error, "the declarations name no schema with one primary key for #{kind}"}
    end
  end

  defp new(%Binding{attributes: attributes}, subject, kind, schema, key) do
    %__MODULE__{subject: subject, attributes: attributes, kind: kind, schema: schema, key: key}
  end

  defp filtered(_plan, %{"kind" => "KIND_ALWAYS_DENIED"}), do: :denied
  defp filtered(_plan, %{"kind" => "KIND_ALWAYS_ALLOWED"}), do: {:ok, dynamic([_row], true)}
  defp filtered(plan, %{"kind" => "KIND_CONDITIONAL", "condition" => condition}), do: operand(plan, condition)
  defp filtered(_plan, other), do: {:error, "the plan carries no filter this adapter reads: " <> abbreviated(other)}

  defp operand(plan, %{"expression" => expression}) when is_map(expression), do: expression(plan, expression)

  defp operand(_plan, other),
    do: {:error, "the plan carries an operand this adapter reads as no expression: " <> abbreviated(other)}

  defp expression(plan, %{"operator" => "and", "operands" => operands}) when is_list(operands) do
    combined(plan, operands, :and)
  end

  defp expression(plan, %{"operator" => "or", "operands" => operands}) when is_list(operands) do
    combined(plan, operands, :or)
  end

  defp expression(plan, %{"operator" => "not", "operands" => [operand]}) do
    with {:ok, expression} <- operand(plan, operand), do: {:ok, dynamic([row], not (^expression))}
  end

  defp expression(plan, %{"operator" => operator, "operands" => [left, right]}) when is_binary(operator) do
    binary(plan, operator, left, right)
  end

  defp expression(_plan, other),
    do: {:error, "the plan uses an expression this adapter does not express: " <> abbreviated(other)}

  defp combined(plan, operands, connective) do
    step = fn operand, {:ok, acc} -> joined(operand(plan, operand), connective, acc) end

    case Enum.reduce_while(operands, {:ok, nil}, step) do
      {:ok, nil} -> {:error, "the plan uses #{connective} with no operands"}
      answer -> answer
    end
  end

  defp joined({:ok, expression}, _connective, nil), do: {:cont, {:ok, expression}}
  defp joined({:ok, expression}, :and, acc), do: {:cont, {:ok, dynamic([row], ^acc and ^expression)}}
  defp joined({:ok, expression}, :or, acc), do: {:cont, {:ok, dynamic([row], ^acc or ^expression)}}
  defp joined({:error, detail}, _connective, _acc), do: {:halt, {:error, detail}}

  # One side names an attribute and the other a value; a comparison of two
  # attributes or of two values is not a rule over the rows.
  defp binary(plan, operator, left, right) do
    case {sided(plan, left), sided(plan, right)} do
      {{:ok, {:source, source}}, {:ok, {:value, value}}} -> applied(plan, operator, source, value)
      {{:ok, {:value, value}}, {:ok, {:source, source}}} -> applied(plan, flipped(operator), source, value)
      {{:error, detail}, _right} -> {:error, detail}
      {_left, {:error, detail}} -> {:error, detail}
      {_left, _right} -> {:error, "the plan compares #{operator} between two sides this adapter cannot place"}
    end
  end

  defp sided(_plan, %{"value" => value}), do: {:ok, {:value, value}}
  defp sided(plan, %{"variable" => name}) when is_binary(name), do: variable(plan, name)
  defp sided(_plan, other), do: {:error, "the plan compares against " <> abbreviated(other)}

  defp variable(plan, name) do
    case String.split(name, ".") do
      ["request", "resource", "attr", attribute] -> declared(plan, attribute)
      ["request", "resource", "id"] -> {:ok, {:source, {:column, plan.key}}}
      _other -> {:error, "the plan reads #{name}, which is no resource attribute"}
    end
  end

  defp declared(%__MODULE__{attributes: attributes, kind: kind}, name) do
    case Enum.find(Attributes.attributes_of(attributes, kind), &(Atom.to_string(&1.name) == name)) do
      %Attribute{source: source} -> {:ok, {:source, source}}
      nil -> {:error, "the plan reads the attribute #{name}, which the declarations do not name"}
    end
  end

  # A value the subquery selected for the asking subject holds of the row,
  # which is membership in the ids it selected with that value.
  defp applied(%__MODULE__{key: key} = plan, "has", {:subquery, fun}, value) when is_binary(value) do
    ids = from(row in subquery(fun.(plan.subject)), where: row.value == ^value, select: row.id)
    {:ok, dynamic([row], field(row, ^key) in subquery(ids))}
  end

  defp applied(plan, "in", {:column, column}, values) when is_list(values) do
    with {:ok, cast} <- cast_all(plan, column, values), do: {:ok, dynamic([row], field(row, ^column) in ^cast)}
  end

  defp applied(plan, operator, {:column, column}, value) do
    with {:ok, cast} <- cast(plan, column, value), do: compared(operator, column, cast)
  end

  defp applied(_plan, operator, {:subquery, _fun}, value) do
    {:error, "the plan uses #{operator} over a subquery attribute and " <> abbreviated(value)}
  end

  defp compared("eq", column, value), do: {:ok, dynamic([row], field(row, ^column) == ^value)}
  defp compared("ne", column, value), do: {:ok, dynamic([row], field(row, ^column) != ^value)}
  defp compared("lt", column, value), do: {:ok, dynamic([row], field(row, ^column) < ^value)}
  defp compared("le", column, value), do: {:ok, dynamic([row], field(row, ^column) <= ^value)}
  defp compared("gt", column, value), do: {:ok, dynamic([row], field(row, ^column) > ^value)}
  defp compared("ge", column, value), do: {:ok, dynamic([row], field(row, ^column) >= ^value)}

  defp compared(operator, _column, _value),
    do: {:error, "the plan uses the operator #{operator}, which this adapter does not express"}

  # `in` reads as membership, so the sides swap into the attribute holding
  # the value; the orderings swap with them.
  defp flipped("in"), do: "has"
  defp flipped("lt"), do: "gt"
  defp flipped("le"), do: "ge"
  defp flipped("gt"), do: "lt"
  defp flipped("ge"), do: "le"
  defp flipped(operator), do: operator

  defp cast_all(plan, column, values) do
    step = fn value, {:ok, acc} ->
      case cast(plan, column, value) do
        {:ok, cast} -> {:cont, {:ok, [cast | acc]}}
        {:error, detail} -> {:halt, {:error, detail}}
      end
    end

    with {:ok, cast} <- Enum.reduce_while(values, {:ok, []}, step), do: {:ok, Enum.reverse(cast)}
  end

  defp cast(%__MODULE__{schema: schema}, column, value) do
    case schema.__schema__(:type, column) do
      nil -> {:error, "the plan reads #{column}, which #{inspect(schema)} does not hold"}
      type -> cast_type(type, column, value)
    end
  end

  defp cast_type(type, column, value) do
    case Ecto.Type.cast(type, value) do
      {:ok, cast} -> {:ok, cast}
      _error -> {:error, "the plan compares #{column} with #{abbreviated(value)}, which the column cannot hold"}
    end
  end

  defp abbreviated(term), do: String.slice(inspect(term), 0, 200)
end
