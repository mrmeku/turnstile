defmodule ExampleFga.Repo.Migrations.Domain do
  @moduledoc false
  use Ecto.Migration

  alias Example.Infrastructure.Migration

  def up, do: Migration.up(app_role: "turnstile_app")
  def down, do: Migration.down()
end
