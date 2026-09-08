defmodule Turnstile.Repo.Matching do
  @moduledoc """
  The three matching rules of the seam, applied to one query:

  1. A query is judged by its root source. A protected root needs a
     decision naming its object type, a carried admission, or an exemption.
  2. A preload or association query is a query of its own, with the
     association's schema as root; it passes when the parent's decision
     carries the association.
  3. Every other protected source in the query, a joined schema or a
     subquery's root, must be admitted the same way.

  A schema is protected iff it declares an object type. Sources without a
  schema, a table name or a fragment, are not judged.
  """

  alias Ecto.Query.JoinExpr
  alias Turnstile.Error
  alias Turnstile.Repo.Caller
  alias Turnstile.Repo.Mediation
  alias Turnstile.Schema

  @doc "Judge a query under a mediation; returns `:ok` or raises `Turnstile.Error.Unmediated`."
  @spec judge(Ecto.Query.t(), Mediation.t() | nil, module()) :: :ok
  def judge(%Ecto.Query{} = query, mediation, repo) when is_atom(repo) do
    root = admit_source(query.from.source, mediation, repo)
    _sources = admit_joins(query.joins, %{0 => root}, mediation, repo)
    :ok
  end

  @doc "Admit one schema under a mediation; returns `:ok` or raises `Turnstile.Error.Unmediated`."
  @spec admit(module() | nil, Mediation.t() | nil, module()) :: :ok
  def admit(schema, mediation, repo) when is_atom(repo) do
    if admitted?(schema, mediation), do: :ok, else: refuse(schema, mediation, repo)
  end

  @doc "Whether a schema passes under a mediation."
  @spec admitted?(module() | nil, Mediation.t() | nil) :: boolean()
  def admitted?(schema, mediation) do
    case Schema.object_type_of(schema) do
      nil -> true
      type -> Mediation.exempt?(mediation) or Mediation.object_type(mediation) == type or schema in carried(mediation)
    end
  end

  defp carried(%Mediation{carried: carried}), do: carried
  defp carried(nil), do: []

  defp admit_source({_table, schema}, mediation, repo) do
    :ok = admit(schema, mediation, repo)
    schema
  end

  defp admit_source(%Ecto.SubQuery{query: inner}, mediation, repo) do
    :ok = judge(inner, mediation, repo)
    root_schema(inner)
  end

  defp admit_source(_other, _mediation, _repo), do: nil

  # Every join's source, keyed by binding index, each admitted as it is met.
  defp admit_joins(joins, sources, mediation, repo) do
    joins
    |> Enum.with_index(1)
    |> Enum.reduce(sources, fn {join, index}, sources ->
      Map.put(sources, index, admit_join(join, sources, mediation, repo))
    end)
  end

  defp admit_join(%JoinExpr{source: nil, assoc: {index, field}}, sources, mediation, repo) do
    case Map.get(sources, index) do
      nil ->
        nil

      parent ->
        schema = Mediation.related(parent, field)
        :ok = admit(schema, mediation, repo)
        schema
    end
  end

  defp admit_join(%JoinExpr{source: source}, _sources, mediation, repo), do: admit_source(source, mediation, repo)

  defp root_schema(%Ecto.Query{from: %{source: {_table, schema}}}), do: schema
  defp root_schema(%Ecto.Query{from: %{source: %Ecto.SubQuery{query: inner}}}), do: root_schema(inner)
  defp root_schema(_query), do: nil

  defp refuse(schema, mediation, repo) do
    {name, arity} = call(mediation)

    raise Error.Unmediated,
      function: name,
      arity: arity,
      schema: schema,
      object_type: Mediation.object_type(mediation),
      caller: caller(mediation, repo)
  end

  defp call(%Mediation{call: call}), do: call
  defp call(nil), do: {:prepare_query, 3}

  defp caller(%Mediation{caller: caller}, _repo) when is_atom(caller) and not is_nil(caller), do: caller
  defp caller(_mediation, repo), do: Caller.module(repo)
end
