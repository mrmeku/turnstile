defmodule ExampleCerbos.Repo.Migrations.Domain do
  @moduledoc false
  use Ecto.Migration

  alias Example.Migrations.Domain

  def up, do: Domain.up(app_role: "turnstile_app")
  def down, do: Domain.down()
end
