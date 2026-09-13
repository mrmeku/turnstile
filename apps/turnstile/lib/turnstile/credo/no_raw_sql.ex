if Code.ensure_loaded?(Credo.Check) do
  defmodule Turnstile.Credo.NoRawSQL do
    @moduledoc false
    use Credo.Check,
      id: "TS0001",
      base_priority: :high,
      category: :warning,
      param_defaults: [allow: []],
      explanations: [
        check: """
        Every query to the application's database goes through a repo that
        `use Turnstile.Repo`, where the decision or the exemption that covers
        it is checked. `Ecto.Adapters.SQL.query/4` and its variants, and any
        `Postgrex` call, reach the database around the seam, so nothing
        checks them.

        A module the seam itself relies on, such as a ledger's writer or a
        test cluster's bootstrap, is named in `allow`.
        """,
        params: [allow: "Module name prefixes whose raw SQL is allowed, as strings."]
      ]

    alias Credo.Code.Name

    @sql_functions [:query, :query!, :query_many, :query_many!]

    @doc false
    @impl Credo.Check
    def run(%SourceFile{} = source_file, params) do
      ctx = Context.build(source_file, params, __MODULE__, %{module: nil})
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    end

    defp walk({:defmodule, _meta, [{:__aliases__, _alias_meta, parts}, [do: body]]}, ctx) do
      name = nested(ctx.module, Name.full(parts))
      inner = Credo.Code.prewalk(body, &walk/2, %{ctx | module: name})
      {nil, %{ctx | issues: inner.issues}}
    end

    # The issue points at the alias, where the trigger text starts.
    defp walk({{:., _dot_meta, [{:__aliases__, meta, parts}, function]}, _call_meta, _args} = ast, ctx) do
      case raw(parts, function) do
        nil -> {ast, ctx}
        trigger -> {ast, put_issue(ctx, issue_for(ctx, meta, trigger))}
      end
    end

    defp walk(ast, ctx), do: {ast, ctx}

    defp nested(nil, name), do: name
    defp nested(outer, name), do: outer <> "." <> name

    defp raw([:Ecto, :Adapters, :SQL], function) when function in @sql_functions, do: "Ecto.Adapters.SQL.#{function}"
    defp raw([:SQL], function) when function in @sql_functions, do: "SQL.#{function}"
    defp raw([:Postgrex | _rest] = parts, function), do: Name.full(parts) <> "." <> Atom.to_string(function)
    defp raw(_parts, _function), do: nil

    defp issue_for(ctx, meta, trigger) do
      if allowed?(ctx.module, ctx.params.allow) do
        nil
      else
        format_issue(ctx,
          message: "#{trigger} reaches the database around the seam; call the repo with a decision or an exemption.",
          trigger: trigger,
          line_no: meta[:line],
          column: meta[:column]
        )
      end
    end

    defp allowed?(nil, _allow), do: false
    defp allowed?(module, allow), do: Enum.any?(allow, &String.starts_with?(module, &1))
  end
end
