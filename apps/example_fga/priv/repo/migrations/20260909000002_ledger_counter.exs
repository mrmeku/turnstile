defmodule ExampleFga.Repo.Migrations.LedgerCounter do
  @moduledoc false
  use Ecto.Migration

  alias Turnstile.Ledger.Migration

  def up, do: Migration.counter_up(app_role: "turnstile_app")
  def down, do: Migration.counter_down()
end
