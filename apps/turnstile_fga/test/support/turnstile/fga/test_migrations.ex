defmodule Turnstile.Fga.TestMigrations do
  @moduledoc "The migrations this package's own test run applies; a thin application has its own set."

  use Boundary, top_level?: true, deps: [Ecto.Migration, Turnstile.Fga.Migration]
end

defmodule Turnstile.Fga.TestMigrations.Outbox do
  @moduledoc "Calls the outbox helper and the cursor helper the way a thin application's migration does."
  use Ecto.Migration

  alias Turnstile.Fga.Migration

  @spec up() :: :ok
  def up do
    :ok = Migration.outbox_up()
    Migration.cursor_up()
  end

  @spec down() :: :ok
  def down do
    :ok = Migration.cursor_down()
    Migration.outbox_down()
  end
end
