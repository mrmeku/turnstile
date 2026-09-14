defmodule Turnstile.Fga.MigrationCommittedTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Turnstile.Fga.TestMigrations.Outbox
  alias Turnstile.TestRepos.Owner

  @moduletag :committed

  @exists "SELECT to_regclass('turnstile_fga_outbox') IS NOT NULL"

  test "outbox_down drops the table and outbox_up brings it back" do
    _versions = Ecto.Migrator.run(Owner, [{1, Outbox}], :down, all: true, log: false)
    assert %{rows: [[false]]} = SQL.query!(Owner, @exists)

    _versions = Ecto.Migrator.run(Owner, [{1, Outbox}], :up, all: true, log: false)
    assert %{rows: [[true]]} = SQL.query!(Owner, @exists)
    assert %{rows: []} = SQL.query!(Owner, "SELECT id, object FROM turnstile_fga_outbox")
  end
end
