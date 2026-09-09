defmodule Turnstile.Ledger.CatalogCommittedTest do
  use ExUnit.Case, async: false

  alias Turnstile.Error
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Catalog
  alias Turnstile.Ledger.Genesis
  alias Turnstile.Ledger.TestMigrations.Cascade
  alias Turnstile.Ledger.TestRepos.CommittedOwner
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Committed

  @moduletag :committed

  @schemas [Account, Folder, Membership]
  @migrations [{3, Cascade}]

  setup tags do
    {:ok, _context} = Boot.setup(tags)
  end

  test "a foreign key that deletes or blanks a fact row is refused, and named" do
    assert :ok = Catalog.check(CommittedOwner, @schemas)
    _up = Ecto.Migrator.run(CommittedOwner, @migrations, :up, all: true, log: false)
    on_exit(fn -> _down = Ecto.Migrator.run(CommittedOwner, @migrations, :down, all: true, log: false) end)

    assert {:error, %Error.Invalid{what: :cascade} = error} = Catalog.check(CommittedOwner, @schemas)
    assert error.detail =~ "memberships_folder_cascade on turnstile_fixture_memberships deletes a fact row"
    assert error.detail =~ "memberships_folder_blank on turnstile_fixture_memberships blanks a fact row"
    assert error.detail =~ "when a row of turnstile_fixture_folders goes, and no fact event would say so"

    {Ledger.Ecto, ledger_options} = Committed.ledger()

    assert {:error, %Error.Invalid{what: :cascade}} =
             Genesis.run(ledger_options, @schemas, migration: "the migration that would begin the ledger")

    _down = Ecto.Migrator.run(CommittedOwner, @migrations, :down, all: true, log: false)
    assert :ok = Catalog.check(CommittedOwner, @schemas)
  end
end
