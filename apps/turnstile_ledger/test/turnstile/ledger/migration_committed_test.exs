defmodule Turnstile.Ledger.MigrationCommittedTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Turnstile.Ledger.TestMigrations.Counter
  alias Turnstile.Ledger.TestRepos.CommittedOwner

  @moduletag :committed

  @exists "SELECT to_regclass('turnstile_ledger_counter') IS NOT NULL"

  test "counter_down drops the table and counter_up brings it back with its default row" do
    _versions = Ecto.Migrator.run(CommittedOwner, [{1, Counter}], :down, all: true, log: false)
    assert %{rows: [[false]]} = SQL.query!(CommittedOwner, @exists)

    _versions = Ecto.Migrator.run(CommittedOwner, [{1, Counter}], :up, all: true, log: false)
    assert %{rows: [[true]]} = SQL.query!(CommittedOwner, @exists)
    assert %{rows: [["default", 0]]} = SQL.query!(CommittedOwner, "SELECT name, position FROM turnstile_ledger_counter")
  end
end
