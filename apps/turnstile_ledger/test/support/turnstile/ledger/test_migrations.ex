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
