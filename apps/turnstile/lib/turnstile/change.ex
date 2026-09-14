defmodule Turnstile.Change do
  @moduledoc """
  The change event: one telemetry event for each single-row write to an
  audited schema, computed from the write itself and published inside the
  write's transaction, so a consumer that writes to the same repository
  from its handler joins that transaction.

  The payload carries what a consumer needs to write a record without
  inventing a value:

  | Key | Value |
  |---|---|
  | `operation` | `:create`, `:update`, or `:delete` |
  | `kind` | what the schema declared with `audited/1` |
  | `target` | `{type, id}` of the row that changed |
  | `changes` | each fact field that changed, to `{old, new}` |
  | `actor` | the subject the decision named, or the library |
  | `actor_kind` | the kind of that subject |
  | `time` | the moment from the configured clock |
  | `operation_id` | the identifier every event of one operation shares |
  | `schema` | the Ecto schema module |

  The value before a change is the row the caller loaded, so a change a
  second writer made between the load and the write is not visible here.
  The library publishes the event. It does not store it, and what an
  attached handler does with it is the handler's own business.
  """

  alias Turnstile.Schema

  @event [:turnstile, :change]
  @library {:non_person_entity, "00000000-0000-0000-0000-000000000000"}

  @typedoc "What the write did to the row."
  @type operation :: :create | :update | :delete

  @typedoc "What every event of one operation shares: who asked, the identifier, and the moment."
  @type stamp :: %{by: Turnstile.subject(), operation_id: Turnstile.Id.t(), at: DateTime.t()}

  @doc "The telemetry event a change publishes, which is what a consumer attaches to."
  @spec event() :: [atom()]
  def event, do: @event

  @doc """
  The actor of a change no decision named, which is the library itself: a
  non-person entity with the nil identifier. A write through the seam under
  an exemption carries this.
  """
  @spec library() :: Turnstile.subject()
  def library, do: @library

  @doc "Publish one change. The row before an insert and the row after a delete are `nil`."
  @spec publish(module(), operation(), struct() | nil, struct() | nil, stamp()) :: :ok
  def publish(schema, operation, old, new, stamp) when is_atom(schema) and is_map(stamp) do
    :telemetry.execute(@event, %{}, payload(schema, operation, old, new, stamp))
  end

  @doc "The payload one change makes, which is what `publish/5` sends."
  @spec payload(module(), operation(), struct() | nil, struct() | nil, stamp()) :: map()
  def payload(schema, operation, old, new, stamp) when is_atom(schema) and is_map(stamp) do
    {kind, _id} = stamp.by

    %{
      operation: operation,
      kind: Schema.kind_of(schema),
      target: target(schema, new || old),
      changes: changes(schema, old, new),
      actor: stamp.by,
      actor_kind: kind,
      time: stamp.at,
      operation_id: stamp.operation_id,
      schema: schema
    }
  end

  # The type a consumer names the row by: the object type where the schema
  # protects one, and the kind it is audited as where it protects none,
  # which is what a subject schema such as an account table declares.
  defp target(schema, row) do
    type = Schema.object_type_of(schema) || Schema.kind_of(schema)

    {type, id(schema, row)}
  end

  defp id(schema, row) do
    case schema.__schema__(:primary_key) do
      [key] -> Map.get(row, key)
      keys -> Map.new(keys, &{&1, Map.get(row, &1)})
    end
  end

  defp changes(schema, old, new) do
    schema
    |> Schema.fact_columns()
    |> Enum.flat_map(&changed(&1, value(old, &1), value(new, &1)))
    |> Map.new()
  end

  defp changed(_column, same, same), do: []
  defp changed(column, before, now), do: [{column, {before, now}}]

  defp value(nil, _column), do: nil
  defp value(row, column), do: Map.get(row, column)
end
