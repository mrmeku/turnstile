defmodule Turnstile.Repo.Source do
  @moduledoc """
  The root source of what a Repo function was handed: a schema module, a
  table name, or `nil`. A query answers with its `from`, through a subquery;
  a struct with its schema; a list with its first element; a changeset with
  its data; `{source, schema}` with the schema.
  """

  @type root :: module() | String.t() | nil

  @doc "The root source."
  @spec root(term()) :: root()
  def root(%Ecto.Query{from: %{source: {table, nil}}}), do: table
  def root(%Ecto.Query{from: %{source: {_table, schema}}}), do: schema
  def root(%Ecto.Query{from: %{source: %Ecto.SubQuery{query: inner}}}), do: root(inner)
  def root(%Ecto.Query{}), do: nil
  def root(%Ecto.Changeset{data: data}), do: root(data)
  def root(%{__struct__: schema}), do: schema
  def root([first | _rest]), do: root(first)
  def root([]), do: nil
  def root(nil), do: nil
  def root({source, schema}) when is_binary(source) and is_atom(schema), do: schema
  def root(source) when is_binary(source), do: source
  def root(module) when is_atom(module), do: module

  @doc "A query for `around_query/3`: the queryable as a query, a struct's schema as a query, or `nil`."
  @spec to_query(term()) :: Ecto.Query.t() | nil
  def to_query(%Ecto.Query{} = query), do: query
  def to_query(%Ecto.Changeset{data: data}), do: to_query(data)
  def to_query(%{__struct__: schema}), do: to_query(schema)
  def to_query([first | _rest]), do: to_query(first)
  def to_query([]), do: nil
  def to_query(nil), do: nil
  def to_query(module) when is_atom(module), do: Ecto.Queryable.to_query(module)
  def to_query(other), do: Ecto.Queryable.to_query(other)
end
