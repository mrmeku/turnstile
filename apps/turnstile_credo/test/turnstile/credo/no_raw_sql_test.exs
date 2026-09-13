defmodule Turnstile.Credo.NoRawSQLTest do
  use Credo.Test.Case, async: true

  alias Turnstile.Credo.NoRawSQL

  # Credo is a compile-time dependency; its parser services run as an
  # application. Under `mix quality` the credo task has already started that
  # application's supervisor in this VM, which the start reports as
  # already_started; the services are up either way.
  setup_all do
    case Application.ensure_all_started(:credo) do
      {:ok, _started} -> :ok
      {:error, {:credo, {{:already_started, _pid}, _start}}} -> :ok
    end
  end

  test "a query through Ecto.Adapters.SQL, aliased or not, and a Postgrex call are flagged" do
    """
    defmodule Report do
      alias Ecto.Adapters.SQL

      def run(repo) do
        Ecto.Adapters.SQL.query!(repo, "SELECT 1")
        SQL.query(repo, "SELECT 1")
        Postgrex.query!(conn(), "SELECT 1", [])
      end
    end
    """
    |> to_source_file()
    |> run_check(NoRawSQL)
    |> assert_issues(fn issues ->
      assert Enum.sort(Enum.map(issues, & &1.trigger)) == ["Ecto.Adapters.SQL.query!", "Postgrex.query!", "SQL.query"]
    end)
  end

  test "a module under an allowed prefix passes, and a nested module keeps its own name" do
    """
    defmodule Turnstile.Ledger.Writer do
      def run(repo), do: Ecto.Adapters.SQL.query!(repo, "SELECT 1")

      defmodule Inner do
        def run(repo), do: Ecto.Adapters.SQL.query!(repo, "SELECT 1")
      end
    end

    defmodule Other do
      def run(repo), do: Ecto.Adapters.SQL.query!(repo, "SELECT 1")
    end
    """
    |> to_source_file()
    |> run_check(NoRawSQL, allow: ["Turnstile.Ledger"])
    |> assert_issue(fn issue -> assert issue.line_no == 10 end)
  end

  test "a repo call with an exemption is not raw SQL" do
    """
    defmodule Report do
      def run(repo), do: repo.query!("SELECT 1", [], turnstile: {:exempt, "report"})
    end
    """
    |> to_source_file()
    |> run_check(NoRawSQL)
    |> refute_issues()
  end
end
