defmodule Turnstile.Postgres.ReplayTest do
  use ExUnit.Case, async: false

  alias Turnstile.Fixture.Tables
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Conformance.Rules
  alias Turnstile.Postgres.Replay
  alias Turnstile.Postgres.Session
  alias Turnstile.Postgres.Settings
  alias Turnstile.Subject
  alias Turnstile.Test.Cluster
  alias Turnstile.TestRepos.Owner

  @exemption {:exempt, :library}
  @at ~U[2026-09-09 12:00:00Z]
  @folder 8_001
  @tables ~w(
    turnstile_fixture_accounts
    turnstile_fixture_folders
    turnstile_fixture_items
    turnstile_fixture_memberships
  )

  setup do
    truncate!()
    on_exit(&truncate!/0)
    :ok
  end

  test "the version's policies come back as the text they were read from" do
    text = version()

    Cluster.scratch!(Cluster.info(), [{Owner, :owner}], fn %{Owner => scratch} ->
      migrate!()
      :ok = Replay.build!(Owner, tables: @tables, from: Owner, to: scratch, policies: text)
      assert version() == text
    end)
  end

  test "a database of its own answers by the state that was written into it and the version's rules" do
    population!()
    text = version()
    assert reads?("ann", @folder)

    _revoked = statement!("DELETE FROM turnstile_fixture_memberships")
    refute reads?("ann", @folder)

    Cluster.scratch!(Cluster.info(), [{Owner, :owner}], fn %{Owner => scratch} ->
      migrate!()
      :ok = Replay.build!(Owner, tables: @tables, from: Owner, to: scratch, policies: text, state: &membership!/0)
      assert reads?("ann", @folder)
      refute reads?("bob", @folder)
    end)

    refute reads?("ann", @folder)
  end

  # What the fixture database holds, with ids of its own so a row is written
  # without reading one back: an insert that returns a row needs a policy
  # admitting the read, and outside a decision none does.
  defp population! do
    _account = statement!("INSERT INTO turnstile_fixture_accounts (id, clearance) VALUES ('ann', 'cleared')")
    _folder = statement!("INSERT INTO turnstile_fixture_folders (id, name) VALUES (#{@folder}, 'plans')")
    membership!()
  end

  defp membership! do
    columns = "(id, account_id, role, folder_id)"

    _membership =
      statement!("INSERT INTO turnstile_fixture_memberships #{columns} VALUES (1, 'ann', 'reader', #{@folder})")

    :ok
  end

  defp migrate! do
    :ok = Tables.create!(Owner)
    [_rls] = Ecto.Migrator.run(Owner, [{Rules.version(), Rules}], :up, all: true, log: false)
    :ok
  end

  # Whether the read policy of the version in force admits that folder to
  # that account, under the settings a decision sets.
  defp reads?(account, folder) do
    settings = Settings.of(%Subject{id: account, kind: :user}, :read, @at)

    Session.around(Owner, settings, fn ->
      %{rows: rows} = statement!("SELECT id FROM turnstile_fixture_folders WHERE id = $1", [folder])
      rows != []
    end)
  end

  defp version, do: Catalog.to_text(Catalog.policies!(Owner, Rules.tables()))

  defp truncate!, do: statement!("TRUNCATE #{Enum.join(@tables, ", ")}")

  defp statement!(sql, params \\ []), do: Owner.query!(sql, params, turnstile: @exemption)
end
