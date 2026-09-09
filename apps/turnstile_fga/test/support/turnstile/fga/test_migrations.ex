defmodule Turnstile.Fga.TestMigrations do
  @moduledoc "The migrations this package's own test run applies; a thin application has its own set."

  use Boundary, top_level?: true, deps: [Ecto.Migration, Turnstile.Fga.Migration]
end

defmodule Turnstile.Fga.TestMigrations.Checkpoint do
  @moduledoc "Calls the checkpoint helper the way a thin application's migration does."
  use Ecto.Migration

  alias Turnstile.Fga.Migration

  @spec up() :: :ok
  def up, do: Migration.checkpoint_up()

  @spec down() :: :ok
  def down, do: Migration.checkpoint_down()
end
