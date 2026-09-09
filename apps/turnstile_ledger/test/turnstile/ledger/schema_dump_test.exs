defmodule Turnstile.Ledger.SchemaDumpTest do
  use ExUnit.Case, async: false

  alias Turnstile.Ledger.SchemaDump
  alias Turnstile.Ledger.TestRepos

  @directory "tmp/loaded_migrations"
  @output "tmp/schema/loaded.sql"

  setup do
    File.mkdir_p!(@directory)
    on_exit(fn -> File.rm_rf!(@directory) end)
    on_exit(fn -> File.rm_rf!(Path.dirname(@output)) end)
    :ok
  end

  test "a migrations directory is loaded once and run on every database of the cluster" do
    File.write!(Path.join(@directory, "20260908000001_counter.exs"), """
    defmodule Turnstile.Ledger.TestMigrations.Loaded do
      use Ecto.Migration

      def up, do: Turnstile.Ledger.Migration.counter_up()
      def down, do: Turnstile.Ledger.Migration.counter_down()
    end
    """)

    assert SchemaDump.dump(repo: TestRepos.Dump, output: @output, migrations: @directory) == @output
    assert File.read!(@output) =~ "CREATE TABLE public.turnstile_ledger_counter"
    assert Code.ensure_loaded?(Turnstile.Ledger.TestMigrations.Loaded)
  end
end
