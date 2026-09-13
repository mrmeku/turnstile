if Code.ensure_loaded?(Credo.Check) do
  defmodule Turnstile.Credo.UnmediatedRepo do
    use Credo.Check,
      id: "TS0002",
      base_priority: :high,
      category: :warning,
      explanations: [
        check: """
        A module that `use Ecto.Repo` without `use Turnstile.Repo` answers
        every query with no decision checked. The seam is a second `use`
        after Ecto's:

            use Ecto.Repo, otp_app: :my_app, adapter: Ecto.Adapters.Postgres
            use Turnstile.Repo
        """
      ]

    @doc false
    @impl Credo.Check
    def run(%SourceFile{} = source_file, params) do
      ctx = Context.build(source_file, params, __MODULE__)
      result = Credo.Code.prewalk(source_file, &walk/2, ctx)
      result.issues
    end

    defp walk({:defmodule, _meta, [{:__aliases__, _alias_meta, _parts}, [do: body]]} = ast, ctx) do
      uses = Credo.Code.prewalk(body, &collect_use/2, [])

      case {List.keyfind(uses, [:Ecto, :Repo], 0), List.keyfind(uses, [:Turnstile, :Repo], 0)} do
        {{_ecto, meta}, nil} -> {ast, put_issue(ctx, issue_for(ctx, meta))}
        _other -> {ast, ctx}
      end
    end

    defp walk(ast, ctx), do: {ast, ctx}

    # A nested module's `use` lines are its own.
    defp collect_use({:defmodule, _meta, _args}, uses), do: {nil, uses}

    defp collect_use({:use, meta, [{:__aliases__, _alias_meta, parts} | _opts]} = ast, uses),
      do: {ast, [{parts, meta} | uses]}

    defp collect_use(ast, uses), do: {ast, uses}

    defp issue_for(ctx, meta) do
      format_issue(ctx,
        message: "use Ecto.Repo without use Turnstile.Repo: every query on this repo runs unchecked.",
        trigger: "use Ecto.Repo",
        line_no: meta[:line],
        column: meta[:column]
      )
    end
  end
end
