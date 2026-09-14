defmodule Turnstile.Fixture.Migrations do
  @moduledoc "The fixture tables as a migration, which the schema-dump test runs and writes out."

  use Boundary, top_level?: true, deps: [Ecto.Migration, Turnstile.Fixture.Tables]
end

defmodule Turnstile.Fixture.Migrations.Tables do
  @moduledoc "Creates the fixture tables and the application role's grants."

  use Ecto.Migration

  alias Turnstile.Fixture

  @names ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders turnstile_fixture_accounts)

  @doc "Create them."
  @spec up() :: :ok
  def up, do: Fixture.Tables.create!(repo())

  @doc "Drop them, children first."
  @spec down() :: :ok
  def down, do: Enum.each(@names, &execute("DROP TABLE #{&1}"))
end
