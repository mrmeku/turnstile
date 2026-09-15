defmodule Turnstile.Fga.Relay.MigrationTest do
  use ExUnit.Case, async: false

  alias Turnstile.Fga.TestMigrations
  alias Turnstile.TestRepos.Owner

  @moduletag :committed

  @table "turnstile_relay_cursor"
  @migration [{1, TestMigrations.Outbox}]

  test "the cursor table the helper raises can be taken back down and raised again" do
    assert Ecto.Migrator.run(Owner, @migration, :down, all: true, log: false) == [1]
    refute there?(@table)

    assert Ecto.Migrator.run(Owner, @migration, :up, all: true, log: false) == [1]
    assert there?(@table)
  end

  defp there?(table) do
    %{rows: [[count]]} = Owner.query!("SELECT count(*) FROM information_schema.tables WHERE table_name = $1", [table])

    count == 1
  end
end
