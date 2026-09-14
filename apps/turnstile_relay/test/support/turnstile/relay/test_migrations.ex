defmodule Turnstile.Relay.TestMigrations do
  @moduledoc "The migration this package's own test run applies; an application has its own set."

  use Boundary, top_level?: true, deps: [Ecto.Migration, Turnstile.Relay.Migration]
end

defmodule Turnstile.Relay.TestMigrations.Cursor do
  @moduledoc "Calls the cursor helper the way an application's migration does."
  use Ecto.Migration

  alias Turnstile.Relay.Migration

  @spec up() :: :ok
  def up, do: Migration.cursor_up()

  @spec down() :: :ok
  def down, do: Migration.cursor_down()
end
