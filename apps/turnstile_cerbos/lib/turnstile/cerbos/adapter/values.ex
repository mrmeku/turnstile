defmodule Turnstile.Cerbos.Adapter.Values do
  @moduledoc false
  # The values of the declared attributes, read through the bound repo as a
  # library caller: one query for the columns of a kind, one for each
  # subquery an attribute names, built from the subject and the environment
  # the port stamped the request with.
  #
  # Every declared attribute is sent, whether or not the row holds it: a
  # column with nothing in it goes as null and a subquery that selected
  # nothing goes as the empty list. The reason is what the sidecar does with
  # an attribute that is absent: it records an evaluation error against the
  # request rather than reading the attribute as empty, so the record of the
  # decision would carry a fault where the answer is sound.
  #
  # Each value crosses to JSON through the codec, which is the same encoding
  # a plan compiled from the same policy compares a column against.
  #
  # A repo that raises is left to raise. The port turns any exception a
  # decider raises into the engine error that denies, so this package names
  # no driver's error, and a driver it does not carry needs no clause of its
  # own.
  #
  # The request-time facts go with the subject's own attributes, under the
  # name `Turnstile.Cerbos.Attribute.reserved/0`, and `environment/2` builds
  # them: the moment the port stamped the request with, always, and each fact
  # an `environment` block declared, whether the caller supplied it or not.
  # Every moment among them is cut to the second first. A policy compares
  # them as text, while a plan compiled from that same policy compares a
  # column of the same moment in the database, and the two readings agree only
  # where both sides carry the same precision.

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Turnstile.Cerbos.Attribute
  alias Turnstile.Cerbos.Attributes
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Core.Codec

  @exemption {:exempt, :library}

  @doc "The subject's own attributes, from the declarations of its kind, with the request-time facts beside them."
  @spec principal(Binding.t(), Turnstile.subject(), Turnstile.environment()) ::
          {:ok, Attribute.values()} | {:error, String.t()}
  def principal(%Binding{} = binding, {kind, id} = subject, %{now: _now} = request) do
    with {:ok, by_id} <- of(binding, subject, kind, [id], request) do
      own = Map.fetch!(by_id, to_string(id))
      {:ok, Map.put(own, Attribute.reserved(), environment(binding, request))}
    end
  end

  @doc "The request-time facts: the moment the port stamped the request with, and each declared fact."
  @spec environment(Binding.t(), Turnstile.environment()) :: Attribute.values()
  def environment(%Binding{attributes: attributes}, %{now: _now} = request) do
    declared = Map.new(Attributes.facts(attributes), &{&1, Codec.moment(Map.get(request, &1))})
    Map.put(declared, :now, Codec.moment(request.now))
  end

  @doc "The attributes of each object of one type, by the object's id as text."
  @spec resources(Binding.t(), Turnstile.subject(), atom(), [Turnstile.object()], Turnstile.environment()) ::
          {:ok, %{String.t() => Attribute.values()}} | {:error, String.t()}
  def resources(%Binding{} = binding, {_kind, _account} = subject, kind, objects, %{now: _now} = request)
      when is_atom(kind) and is_list(objects) do
    of(binding, subject, kind, Enum.map(objects, &elem(&1, 1)), request)
  end

  @doc "The attributes of the ids of one kind, every declared name present."
  @spec of(Binding.t(), Turnstile.subject(), atom(), [term()], Turnstile.environment()) ::
          {:ok, %{String.t() => Attribute.values()}} | {:error, String.t()}
  def of(%Binding{} = binding, {_kind, _account} = subject, kind, ids, %{now: _now} = request)
      when is_atom(kind) and is_list(ids) do
    declared = Attributes.attributes_of(binding.attributes, kind)

    with {:ok, from_columns} <- columns(binding, kind, ids, declared) do
      from_subqueries = subqueries(binding, subject, request, ids, declared)
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
    rows = all(repo, query)

    {:ok, Map.new(rows, fn {id, values} -> {to_string(id), named(attributes, values)} end)}
  end

  defp named(attributes, values) do
    Map.new(attributes, fn %Attribute{name: name, source: {:column, column}} -> {name, Codec.encode(values[column])} end)
  end

  defp subqueries(binding, subject, request, ids, declared) do
    declared
    |> Enum.reject(&Attribute.column?/1)
    |> Enum.reduce(%{}, fn attribute, acc ->
      gathered(acc, attribute.name, read_subquery(binding, subject, request, ids, attribute))
    end)
  end

  defp read_subquery(binding, subject, request, ids, %Attribute{source: {:subquery, fun}}) do
    query = from(row in subquery(fun.(subject, request)), where: row.id in ^ids, select: {row.id, row.value})
    all(binding.repo, query)
  end

  # The values of one attribute, gathered per row into the list the row's
  # other attributes are already in.
  defp gathered(acc, name, rows) do
    rows
    |> Enum.group_by(fn {id, _value} -> to_string(id) end, fn {_id, value} -> Codec.encode(value) end)
    |> Enum.reduce(acc, fn {key, values}, into ->
      Map.update(into, key, %{name => values}, &Map.put(&1, name, values))
    end)
  end

  defp all(repo, query), do: repo.all(query, turnstile: @exemption)
end
