defmodule Example.Fixture.Migration do
  @moduledoc "The one migration the example's own suite runs: the domain helper, as a thin application's first migration calls it."

  use Boundary, top_level?: true, deps: [Example, Ecto.Migration]
  use Ecto.Migration

  alias Example.Infrastructure.Migration

  @spec up() :: :ok
  def up, do: Migration.up(app_role: "turnstile_app")

  @spec down() :: :ok
  def down, do: Migration.down()
end
