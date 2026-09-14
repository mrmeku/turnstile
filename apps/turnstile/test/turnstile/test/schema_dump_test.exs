defmodule Turnstile.Test.SchemaDumpTest do
  use ExUnit.Case, async: false

  alias Turnstile.Test.SchemaDump
  alias Turnstile.TestRepos

  @directory "tmp/loaded_migrations"
  @output "tmp/schema/loaded.sql"

  setup do
    File.mkdir_p!(@directory)
    on_exit(fn -> File.rm_rf!(@directory) end)
    on_exit(fn -> File.rm_rf!(Path.dirname(@output)) end)
    :ok
  end

  test "a migrations directory is loaded once and run on every database of the cluster" do
    File.write!(Path.join(@directory, "20260908000001_accounts.exs"), """
    defmodule Turnstile.Fixture.Migrations.Loaded do
      use Ecto.Migration

      def up, do: execute("CREATE TABLE turnstile_fixture_loaded (id bigserial PRIMARY KEY)")
      def down, do: execute("DROP TABLE turnstile_fixture_loaded")
    end
    """)

    assert SchemaDump.dump(repo: TestRepos.Dump, output: @output, migrations: @directory) == @output
    assert File.read!(@output) =~ "CREATE TABLE public.turnstile_fixture_loaded"
    assert Code.ensure_loaded?(Turnstile.Fixture.Migrations.Loaded)
  end
end
