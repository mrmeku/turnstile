defmodule Turnstile.Cerbos.Coverage do
  @moduledoc """
  Declared-fact coverage for a compiled query plan: every column the query
  reads is a declared fact.

  A plan comes from the sidecar and becomes a query here, which is the one
  place where what a policy reads turns into what the database reads. So
  the check is on the query: it is walked, subqueries included, every field
  reference is collected by the schema of the source it names, and each is
  set against the declarations of that schema. A column is declared when the
  schema's `fact` names it as the column, the subject, or the object, when
  its `relationship` names it as the subject, the object, or an attribute,
  when it is the primary key, or when it is the foreign key of a relation
  some declared schema carries, through the closure of what the carried
  schemas carry in turn. A fragment cannot be walked, so it is the finding
  `{:fragment, text}`.

  The schemas the closure starts from are the ones the attribute
  declarations name, since those are the schemas this adapter reads at all.
  A read of a column no declaration covers is a fact that never went
  through the seam, which is what this check exists to catch.
  """

  alias Turnstile.Cerbos.Attributes
  alias Turnstile.Schema
  alias Turnstile.Schema.Fact
  alias Turnstile.Schema.Relationship

  @typedoc "An undeclared read: the schema and the column, or a fragment's text."
  @type finding :: {module(), atom()} | {:fragment, String.t()}

  @doc "Ok, or the undeclared reads of the query, sorted and without repeats."
  @spec check(Attributes.t(), Ecto.Queryable.t()) :: :ok | {:error, [finding()]}
  def check(attributes, queryable) when is_atom(attributes) do
    case undeclared(attributes, queryable) do
      [] -> :ok
      findings -> {:error, findings}
    end
  end

  @doc "`check/2`, raising with the findings named."
  @spec check!(Attributes.t(), Ecto.Queryable.t()) :: :ok
  def check!(attributes, queryable) when is_atom(attributes) do
    case check(attributes, queryable) do
      :ok ->
        :ok

      {:error, findings} ->
        raise ArgumentError, "the query reads columns #{inspect(attributes)} does not declare: #{describe(findings)}"
    end
  end

  @doc "Every undeclared read the query makes."
  @spec undeclared(Attributes.t(), Ecto.Queryable.t()) :: [finding()]
  def undeclared(attributes, queryable) when is_atom(attributes) do
    carried = carried(attributes)

    queryable
    |> reads()
    |> Enum.reject(&declared?(&1, carried))
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc "Every read the query makes, as findings before the declared ones are removed."
  @spec reads(Ecto.Queryable.t()) :: [finding()]
  def reads(queryable), do: walk_query(Ecto.Queryable.to_query(queryable))

  defp describe(findings) do
    Enum.map_join(findings, ", ", fn
      {:fragment, text} -> "fragment #{inspect(text)}"
      {schema, column} -> "#{column} of #{inspect(schema)}"
    end)
  end

  defp declared?({:fragment, _text}, _carried), do: false
  defp declared?({nil, _column}, _carried), do: true
  defp declared?({schema, column}, carried), do: column in own_declarations(schema) or {schema, column} in carried

  # The foreign key of every relation a declared schema carries, on the
  # schema that holds it, through the closure of what the carried schemas
  # carry in turn.
  defp carried(attributes) do
    roots = for {_side, _kind, schema} <- Attributes.kinds(attributes), do: schema

    for schema <- closure(roots, []),
        name <- Schema.carries_of(schema),
        {held_by, key} = foreign_key(schema.__schema__(:association, name)),
        held_by != nil,
        do: {held_by, key}
  end

  defp closure([], seen), do: Enum.reverse(seen)

  defp closure([schema | rest], seen) do
    if schema in seen do
      closure(rest, seen)
    else
      next = for name <- Schema.carries_of(schema), related = related(schema, name), related != nil, do: related
      closure(rest ++ next, [schema | seen])
    end
  end

  defp related(schema, name) do
    case schema.__schema__(:association, name) do
      %{related: related} -> related
      _through -> nil
    end
  end

  # The primary key, the columns the facts name, and the columns the relationship names.
  defp own_declarations(schema) do
    facts =
      for %Fact{column: column, subject: subject, object: object} <- Schema.facts_of(schema),
          do: [column, subject, object]

    relationship =
      case Schema.relationship_of(schema) do
        %Relationship{subject: subject, object: object, attributes: attributes} -> [subject, object | attributes]
        nil -> []
      end

    Enum.reject(schema.__schema__(:primary_key) ++ List.flatten(facts) ++ relationship, &is_nil/1)
  end

  defp foreign_key(%Ecto.Association.Has{related: related, related_key: key}), do: {related, key}
  defp foreign_key(%Ecto.Association.BelongsTo{owner: owner, owner_key: key}), do: {owner, key}
  defp foreign_key(_other), do: {nil, nil}

  # Every field reference in a query, by the schema of the source it names.
  defp walk_query(%Ecto.Query{} = query) do
    sources = [source_schema(query.from.source) | Enum.map(query.joins, &source_schema(&1.source))]
    Enum.flat_map(exprs(query), &walk_expr(&1.expr, &1.subqueries || [], sources))
  end

  defp exprs(%Ecto.Query{} = query) do
    clauses = query.wheres ++ query.havings ++ query.order_bys ++ query.group_bys
    joins = Enum.map(query.joins, &%{expr: &1.on.expr, subqueries: Map.get(&1.on, :subqueries)})
    List.wrap(query.select) ++ clauses ++ joins
  end

  defp source_schema({_table, schema}) when is_atom(schema), do: schema
  defp source_schema(_subquery_or_fragment), do: nil

  defp walk_expr({{:., _dot, [{:&, _binding, [index]}, field]}, _meta, []}, _subqueries, sources) do
    [{Enum.at(sources, index), field}]
  end

  defp walk_expr({:subquery, index}, subqueries, _sources) do
    %Ecto.SubQuery{query: query} = Enum.at(subqueries, index)
    walk_query(query)
  end

  defp walk_expr({:fragment, _meta, parts}, _subqueries, _sources) do
    [{:fragment, Enum.map_join(parts, "", &fragment_part/1)}]
  end

  defp walk_expr({_op, _meta, args}, subqueries, sources) when is_list(args) do
    Enum.flat_map(args, &walk_expr(&1, subqueries, sources))
  end

  defp walk_expr({left, right}, subqueries, sources) do
    walk_expr(left, subqueries, sources) ++ walk_expr(right, subqueries, sources)
  end

  defp walk_expr(list, subqueries, sources) when is_list(list) do
    Enum.flat_map(list, &walk_expr(&1, subqueries, sources))
  end

  defp walk_expr(%Ecto.Query.Tagged{value: value}, subqueries, sources), do: walk_expr(value, subqueries, sources)
  defp walk_expr(%{} = map, subqueries, sources), do: walk_expr(Map.to_list(map), subqueries, sources)
  defp walk_expr(_literal, _subqueries, _sources), do: []

  defp fragment_part({:raw, text}), do: text
  defp fragment_part({:expr, _expression}), do: "?"
end
