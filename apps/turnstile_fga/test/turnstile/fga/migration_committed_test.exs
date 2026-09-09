defmodule Turnstile.Fga.MigrationCommittedTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Turnstile.Fga.TestMigrations.Checkpoint
  alias Turnstile.TestRepos.Owner

  @moduletag :committed

  @exists "SELECT to_regclass('turnstile_fga_checkpoint') IS NOT NULL"

  test "checkpoint_down drops the table and checkpoint_up brings it back" do
    _versions = Ecto.Migrator.run(Owner, [{1, Checkpoint}], :down, all: true, log: false)
    assert %{rows: [[false]]} = SQL.query!(Owner, @exists)

    _versions = Ecto.Migrator.run(Owner, [{1, Checkpoint}], :up, all: true, log: false)
    assert %{rows: [[true]]} = SQL.query!(Owner, @exists)
    assert %{rows: []} = SQL.query!(Owner, "SELECT store, position FROM turnstile_fga_checkpoint")
  end
end
