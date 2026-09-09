defmodule ExampleRbac.Repo.Migrations.LedgerEvents do
  @moduledoc false
  use Ecto.Migration

  alias Turnstile.Ledger.Migration

  def up, do: Migration.events_up(app_role: "turnstile_app")
  def down, do: Migration.events_down()
end
