defmodule Turnstile.Cerbos.Values do
  @moduledoc """
  The values of the declared attributes, read through the bound repo as a
  library caller: one query for the columns of a kind, one for each
  subquery an attribute names.

  Every declared attribute is sent, whether or not the row holds it: a
  column with nothing in it goes as null and a subquery that selected
  nothing goes as the empty list. The reason is what the sidecar does with
  an attribute that is absent: it records an evaluation error against the
  request rather than reading the attribute as empty, so the record of the
  decision would carry a fault where the answer is sound.

  A value crosses to JSON as itself where JSON has it, and as text where it
  does not: an `Ecto.Enum` column reaches the sidecar as the string the
  column holds, a date as its ISO 8601 form.
  """

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Turnstile.Cerbos.Attribute
  alias Turnstile.Cerbos.Attributes
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Object
  alias Turnstile.Subject

  @exemption {:exempt, :library}

  @typedoc "The attributes of one row, by the name the declarations gave."
  @type attributes :: %{atom() => term()}

  @doc "The subject's own attributes, from the declarations of its kind."
  @spec principal(Binding.t(), Subject.t()) :: {:ok, attributes()} | {:error, String.t()}
  def principal(%Binding{} = binding, %Subject{id: id} = subject) do
    with {:ok, by_id} <- of(binding, subject, subject.kind, [id]) do
      {:ok, Map.fetch!(by_id, to_string(id))}
    end
  end

  @doc "The attributes of each object of one type, by the object's id as text."
  @spec resources(Binding.t(), Subject.t(), atom(), [Object.t()]) ::
          {:ok, %{String.t() => attributes()}} | {:error, String.t()}
  def resources(%Binding{} = binding, %Subject{} = subject, kind, objects) when is_atom(kind) and is_list(objects) do
    of(binding, subject, kind, Enum.map(objects, & &1.id))
  end

  @doc "The attributes of the ids of one kind, every declared name present."
  @spec of(Binding.t(), Subject.t(), atom(), [term()]) :: {:ok, %{String.t() => attributes()}} | {:error, String.t()}
  def of(%Binding{} = binding, %Subject{} = subject, kind, ids) when is_atom(kind) and is_list(ids) do
    declared = Attributes.attributes_of(binding.attributes, kind)

    with {:ok, from_columns} <- columns(binding, kind, ids, declared),
         {:ok, from_subqueries} <- subqueries(binding, subject, ids, declared) do
      absent = absent(declared)
      {:ok, Map.new(ids, &{to_string(&1), found(absent, from_columns, from_subqueries, to_string(&1))})}
    end
  end

  defp found(absent, from_columns, from_subqueries, key) do
    absent
    |> Map.merge(Map.get(from_columns, key, %{}))
    |> Map.merge(Map.get(from_subqueries, key, %{}))
  end

  # What every declared attribute is worth before a row is read: nothing for
  # a column, nothing selected for a subquery.
  defp absent(declared) do
    Map.new(declared, fn
      %Attribute{name: name, source: {:column, _column}} -> {name, nil}
      %Attribute{name: name, source: {:subquery, _fun}} -> {name, []}
    end)
  end

  defp columns(binding, kind, ids, declared) do
    case Enum.filter(declared, &Attribute.column?/1) do
      [] -> {:ok, %{}}
      attributes -> read_columns(binding, kind, ids, attributes)
    end
  end

  defp read_columns(binding, kind, ids, attributes) do
    case Binding.target(binding, kind) do
      {schema, key} -> selected(binding.repo, schema, key, ids, attributes)
      nil -> {:error, "the declarations name no schema with one primary key for #{kind}"}
    end
  end

  defp selected(repo, schema, key, ids, attributes) do
    names = Enum.map(attributes, fn %Attribute{source: {:column, column}} -> column end)
    query = from(row in schema, where: field(row, ^key) in ^ids, select: {field(row, ^key), map(row, ^names)})

    with {:ok, rows} <- all(repo, query) do
      {:ok, Map.new(rows, fn {id, values} -> {to_string(id), named(attributes, values)} end)}
    end
  end

  defp named(attributes, values) do
    Map.new(attributes, fn %Attribute{name: name, source: {:column, column}} -> {name, json(values[column])} end)
  end

  defp subqueries(binding, subject, ids, declared) do
    declared
    |> Enum.reject(&Attribute.column?/1)
    |> Enum.reduce_while({:ok, %{}}, fn attribute, {:ok, acc} ->
      collected(read_subquery(binding, subject, ids, attribute), attribute.name, acc)
    end)
  end

  defp read_subquery(binding, subject, ids, %Attribute{source: {:subquery, fun}}) do
    all(binding.repo, from(row in subquery(fun.(subject)), where: row.id in ^ids, select: {row.id, row.value}))
  end

  defp collected({:ok, rows}, name, acc), do: {:cont, {:ok, gathered(acc, name, rows)}}
  defp collected({:error, detail}, _name, _acc), do: {:halt, {:error, detail}}

  # The values of one attribute, gathered per row into the list the row's
  # other attributes are already in.
  defp gathered(acc, name, rows) do
    rows
    |> Enum.group_by(fn {id, _value} -> to_string(id) end, fn {_id, value} -> json(value) end)
    |> Enum.reduce(acc, fn {key, values}, into ->
      Map.update(into, key, %{name => values}, &Map.put(&1, name, values))
    end)
  end

  # A read is an edge: a connection that is gone and a value the query
  # cannot cast are failures the caller turns into a denial, not a raise.
  defp all(repo, query) do
    {:ok, repo.all(query, turnstile: @exemption)}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error, Ecto.Query.CastError] -> {:error, Exception.message(error)}
  end

  defp json(nil), do: nil
  defp json(true), do: true
  defp json(false), do: false
  defp json(value) when is_atom(value), do: Atom.to_string(value)
  defp json(%Date{} = value), do: Date.to_iso8601(value)
  defp json(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp json(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp json(%Time{} = value), do: Time.to_iso8601(value)
  defp json(value), do: value
end
