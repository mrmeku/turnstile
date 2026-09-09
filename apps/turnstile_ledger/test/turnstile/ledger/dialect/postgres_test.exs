defmodule Turnstile.Ledger.Dialect.PostgresTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Ledger.Catalog
  alias Turnstile.Ledger.Dialect.Postgres
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot

  setup tags do
    Boot.setup(tags)
  end

  test "the callbacks that answer with a constant answer what the reference dialect answers" do
    assert Postgres.rows_back() == :returning
    assert Postgres.fact_insert_batch() == 2_000
    assert Postgres.reader() == :counter_row
    assert Postgres.lock_clause() == "FOR UPDATE"
  end

  test "a take advances the counter row by the count and answers the last position it took", context do
    assert {:ok, 3} = Postgres.take(TestRepos.App, context.counter, 3)
    assert {:ok, 5} = Postgres.take(TestRepos.App, context.counter, 2)
  end

  test "a take against a counter row that does not exist answers an engine error", context do
    assert {:error, %Error.Engine{operation: :take, detail: detail}} = Postgres.take(TestRepos.App, "absent", 1)
    assert detail =~ "no counter row named"
    assert {:ok, 1} = Postgres.take(TestRepos.App, context.counter, 1)
  end

  test "the append-only grant gives the application role insert and select on the table and its sequence" do
    assert Postgres.append_only_grant("turnstile_ledger_events", "turnstile_app") == [
             "GRANT SELECT, INSERT ON turnstile_ledger_events TO turnstile_app",
             "GRANT USAGE, SELECT ON SEQUENCE turnstile_ledger_events_id_seq TO turnstile_app"
           ]
  end

  test "the cascade query finds no cascading key into the fixture's fact schemas as they are migrated" do
    tables = Catalog.tables([Turnstile.Fixture.Account, Turnstile.Fixture.Folder, Turnstile.Fixture.Membership])

    assert tables == ["turnstile_fixture_accounts", "turnstile_fixture_memberships"]
    assert {:ok, []} = Postgres.cascades(TestRepos.App, tables)
  end
end
