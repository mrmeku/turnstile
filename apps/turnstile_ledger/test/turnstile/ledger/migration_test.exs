defmodule Turnstile.Ledger.MigrationTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Turnstile.Ledger.Migration
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Test.Sandbox

  setup tags do
    Sandbox.setup(TestRepos.App, tags)
  end

  test "counter_up creates the frozen columns, the default row at 0, and the application role's grants" do
    assert %{rows: [["name", "text", "NO"], ["position", "bigint", "NO"]]} =
             SQL.query!(
               TestRepos.Owner,
               "SELECT column_name::text, data_type::text, is_nullable::text FROM information_schema.columns " <>
                 "WHERE table_name = 'turnstile_ledger_counter' ORDER BY ordinal_position"
             )

    assert %{rows: [["turnstile_owner"]]} =
             SQL.query!(
               TestRepos.Owner,
               "SELECT tableowner::text FROM pg_tables WHERE tablename = 'turnstile_ledger_counter'"
             )

    assert %{rows: [[0]]} =
             SQL.query!(TestRepos.App, "SELECT position FROM turnstile_ledger_counter WHERE name = 'default'")

    assert %{rows: [["INSERT"], ["SELECT"], ["UPDATE"]]} =
             SQL.query!(
               TestRepos.Owner,
               "SELECT privilege_type::text FROM information_schema.role_table_grants " <>
                 "WHERE table_name = 'turnstile_ledger_counter' AND grantee = 'turnstile_app' ORDER BY 1"
             )
  end

  test "the application role can advance the row and cannot delete it" do
    assert %{num_rows: 1} =
             SQL.query!(
               TestRepos.App,
               "UPDATE turnstile_ledger_counter SET position = position + 1 WHERE name = 'default'"
             )

    assert_raise Postgrex.Error, ~r/permission denied/, fn ->
      SQL.query!(TestRepos.App, "DELETE FROM turnstile_ledger_counter")
    end
  end

  test "counter_up validates its options" do
    assert_raise NimbleOptions.ValidationError, fn -> Migration.counter_up(app_role: :atom) end
  end
end
