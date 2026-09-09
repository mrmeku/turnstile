defmodule Turnstile.Ledger.TestMigrations do
  @moduledoc "The migrations the ledger's own test run applies; a thin application has its own set."

  use Boundary, top_level?: true, deps: [Ecto.Migration, Turnstile.Ledger.Migration]
end

defmodule Turnstile.Ledger.TestMigrations.Counter do
  @moduledoc "Calls the counter helper the way a thin application's migration does."
  use Ecto.Migration

  alias Turnstile.Ledger.Migration

  @spec up() :: :ok
  def up, do: Migration.counter_up()

  @spec down() :: :ok
  def down, do: Migration.counter_down()
end

defmodule Turnstile.Ledger.TestMigrations.Events do
  @moduledoc "Calls the events helper the way a thin application's migration does."
  use Ecto.Migration

  alias Turnstile.Ledger.Migration

  @spec up() :: :ok
  def up, do: Migration.events_up()

  @spec down() :: :ok
  def down, do: Migration.events_down()
end

defmodule Turnstile.Ledger.TestMigrations.Cascade do
  @moduledoc """
  The migration the catalog check is meant to refuse: two foreign keys into
  the fixture's membership table, one that deletes a grant when its folder
  goes and one that blanks the folder it names. Neither is ever exercised;
  the check reads the catalog, and a migration like this one is what it is
  there to stop.
  """
  use Ecto.Migration

  @spec up() :: :ok
  def up do
    execute "ALTER TABLE turnstile_fixture_memberships ADD CONSTRAINT memberships_folder_cascade " <>
              "FOREIGN KEY (folder_id) REFERENCES turnstile_fixture_folders(id) ON DELETE CASCADE"

    execute "ALTER TABLE turnstile_fixture_memberships ADD CONSTRAINT memberships_folder_blank " <>
              "FOREIGN KEY (folder_id) REFERENCES turnstile_fixture_folders(id) ON DELETE SET NULL"

    :ok
  end

  @spec down() :: :ok
  def down do
    execute "ALTER TABLE turnstile_fixture_memberships DROP CONSTRAINT memberships_folder_blank"
    execute "ALTER TABLE turnstile_fixture_memberships DROP CONSTRAINT memberships_folder_cascade"
    :ok
  end
end
