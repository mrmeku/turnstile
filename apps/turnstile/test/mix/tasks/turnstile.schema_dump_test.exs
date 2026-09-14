defmodule Mix.Tasks.Turnstile.SchemaDumpTest do
  use ExUnit.Case, async: false

  alias Mix.Tasks.Turnstile.SchemaDump
  alias Turnstile.TestRepos

  @output "tmp/schema/fixture.sql"

  setup do
    File.rm_rf!(Path.dirname(@output))
    on_exit(fn -> File.rm_rf!(Path.dirname(@output)) end)
    Mix.shell(Mix.Shell.Process)
    on_exit(fn -> Mix.shell(Mix.Shell.IO) end)
  end

  test "it writes the schema the migrations produce, without pg_dump's restrict lines, the same on every run" do
    SchemaDump.run([])
    assert_received {:mix_shell, :info, ["wrote " <> @output]}
    first = File.read!(@output)
    assert first =~ "CREATE TABLE public.turnstile_fixture_folders"
    assert first =~ "OWNER TO turnstile_owner"
    assert first =~ "GRANT SELECT,INSERT,DELETE,UPDATE ON TABLE public.turnstile_fixture_folders TO turnstile_app"
    refute first =~ "\\restrict"
    refute first =~ "\\unrestrict"
    refute Process.whereis(TestRepos.Dump)

    SchemaDump.run([])
    assert File.read!(@output) == first
  end

  test "it takes no arguments and the mechanism validates its options" do
    assert_raise Mix.Error, ~r/takes no arguments/, fn -> SchemaDump.run(["--x"]) end
    assert_raise NimbleOptions.ValidationError, fn -> Turnstile.Test.SchemaDump.dump(repo: TestRepos.Dump) end
  end
end
