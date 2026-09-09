defmodule Turnstile.Repo.Facts do
  @moduledoc """
  The fact events a single-row write produces, read from the schema's
  declarations: one event per changed fact column, one per element added
  to or removed from a set-valued column, and for a relationship schema one
  for the row's existence and one per changed attribute. `old` comes from
  the row the seam re-read under the ledger's lock clause, never from the
  changeset's data.

  A set-valued column's element is the subject of the event that carries it,
  referenced by the type the declaration's `element:` names. That is what
  keeps each element its own fact: a fold keys a fact by its subject, its
  object, and its attribute, so elements sharing one subject would share one
  key and removing one of them would erase the set.
  """

  import Ecto.Query, only: [where: 3]

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Schema
  alias Turnstile.Schema.Fact
  alias Turnstile.Schema.Relationship
  alias Turnstile.Subject

  @typedoc "What every event of one operation shares."
  @type stamp :: %{by: Subject.t(), operation_id: Turnstile.Id.t(), at: DateTime.t()}

  @doc "Re-read a row by its primary key under the lock clause, through the mediated repo."
  @spec reread(module(), struct(), String.t() | nil, keyword()) :: struct() | nil
  def reread(repo, %schema{} = row, lock, opts) when is_atom(repo) and is_list(opts) do
    query =
      Enum.reduce(schema.__schema__(:primary_key), Ecto.Queryable.to_query(schema), fn key, query ->
        where(query, [r], field(r, ^key) == ^Map.fetch!(row, key))
      end)

    repo.one(%{query | lock: lock}, Keyword.take(opts, [:turnstile, :prefix]))
  end

  @doc "The events between the row before the write and the row after it; either may be `nil`."
  @spec events(module(), struct() | nil, struct() | nil, stamp()) :: [FactEvent.t()]
  def events(schema, old, new, stamp) when is_atom(schema) and is_map(stamp) do
    row = new || old

    column_events =
      schema
      |> Schema.facts_of()
      |> Enum.flat_map(&fact_events(&1, schema, old, new, row, stamp))

    column_events ++ relationship_events(Schema.relationship_of(schema), schema, old, new, stamp)
  end

  @doc "The fact columns a bulk write touches: the declared columns among `fields`, and the relationship's columns."
  @spec touched(module(), [atom()]) :: [atom()]
  def touched(schema, fields) when is_atom(schema) and is_list(fields) do
    declared = Enum.map(Schema.facts_of(schema), & &1.column) ++ relationship_columns(Schema.relationship_of(schema))
    Enum.filter(fields, &(&1 in declared))
  end

  defp relationship_columns(nil), do: []

  defp relationship_columns(%Relationship{subject: subject, object: object, attributes: attributes}),
    do: [subject, object | attributes]

  defp fact_events(%Fact{element: nil} = fact, schema, old, new, row, stamp) do
    old_value = value(old, fact.column)
    new_value = value(new, fact.column)

    if old_value == new_value do
      []
    else
      [
        event(
          fact.kind,
          subject_ref(fact.subject, row),
          object_ref(fact.object, schema, row),
          fact.column,
          old_value,
          new_value,
          stamp
        )
      ]
    end
  end

  defp fact_events(%Fact{} = fact, schema, old, new, row, stamp) do
    old_set = List.wrap(value(old, fact.column))
    new_set = List.wrap(value(new, fact.column))
    object = object_ref(fact.object, schema, row)

    removed =
      Enum.map(old_set -- new_set, fn element ->
        event(fact.kind, {fact.element, element}, object, fact.column, element, nil, stamp)
      end)

    added =
      Enum.map(new_set -- old_set, fn element ->
        event(fact.kind, {fact.element, element}, object, fact.column, nil, element, stamp)
      end)

    removed ++ added
  end

  defp relationship_events(nil, _schema, _old, _new, _stamp), do: []

  defp relationship_events(%Relationship{} = relationship, schema, old, new, stamp) do
    cond do
      is_nil(old) ->
        [row_event(relationship, schema, new, nil, attributes(relationship, new), stamp)]

      is_nil(new) ->
        [row_event(relationship, schema, old, attributes(relationship, old), nil, stamp)]

      moved?(relationship, old, new) ->
        relationship_events(relationship, schema, old, nil, stamp) ++
          relationship_events(relationship, schema, nil, new, stamp)

      true ->
        attribute_events(relationship, schema, old, new, stamp)
    end
  end

  defp moved?(%Relationship{subject: subject, object: object}, old, new) do
    value(old, subject) != value(new, subject) or value(old, object) != value(new, object)
  end

  defp attribute_events(%Relationship{attributes: attributes} = relationship, schema, old, new, stamp) do
    attributes
    |> Enum.reject(&(value(old, &1) == value(new, &1)))
    |> Enum.map(fn attribute ->
      event(
        :relationship,
        subject_ref(relationship.subject, new),
        object_ref(relationship.object, schema, new),
        attribute,
        value(old, attribute),
        value(new, attribute),
        stamp
      )
    end)
  end

  defp row_event(%Relationship{} = relationship, schema, row, old, new, stamp) do
    event(
      :relationship,
      subject_ref(relationship.subject, row),
      object_ref(relationship.object, schema, row),
      nil,
      old,
      new,
      stamp
    )
  end

  defp attributes(%Relationship{attributes: []}, _row), do: true
  defp attributes(%Relationship{attributes: [attribute]}, row), do: value(row, attribute)
  defp attributes(%Relationship{attributes: attributes}, row), do: Map.new(attributes, &{&1, value(row, &1)})

  defp event(kind, subject_ref, object_ref, attribute, old, new, stamp) do
    %FactEvent{
      kind: kind,
      subject_ref: subject_ref,
      object_ref: object_ref,
      attribute: attribute,
      old: old,
      new: new,
      position: nil,
      operation_id: stamp.operation_id,
      at: stamp.at,
      by: stamp.by
    }
  end

  defp value(nil, _column), do: nil
  defp value(row, column), do: Map.get(row, column)

  defp subject_ref(nil, _row), do: nil
  defp subject_ref(column, row), do: {:user, value(row, column)}

  defp object_ref(nil, _schema, _row), do: nil

  defp object_ref(column, schema, row) do
    case object_type_of(schema, column) do
      nil ->
        raise Error.Invalid,
          what: :fact_mapping,
          detail: "#{inspect(schema)}.#{column} names no object type: declare object_type on the schema it refers to"

      type ->
        {type, value(row, column)}
    end
  end

  # The column is the row's own key, or the owner key of an association whose
  # schema declares the type.
  defp object_type_of(schema, column) do
    if column in schema.__schema__(:primary_key) do
      Schema.object_type_of(schema)
    else
      :associations
      |> schema.__schema__()
      |> Enum.map(&schema.__schema__(:association, &1))
      |> Enum.find_value(fn
        %{owner_key: ^column, related: related} -> Schema.object_type_of(related)
        _other -> nil
      end)
    end
  end
end
