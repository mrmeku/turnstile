defmodule Turnstile.Dev.TestMigration do
  @moduledoc """
  One table as a migration, which the cluster runs on each of its databases
  and the schema-dump test writes out: a row the application role may read
  and write, owned by the owner role.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration]
  use Ecto.Migration

  @table "turnstile_dev_rows"

  @doc "Create the table and the application role's grant."
  @spec up() :: :ok
  def up do
    execute("CREATE TABLE #{@table} (id bigserial PRIMARY KEY, name text)")
    execute("GRANT SELECT, INSERT, UPDATE, DELETE ON #{@table} TO turnstile_app")
    execute("GRANT USAGE, SELECT ON SEQUENCE #{@table}_id_seq TO turnstile_app")
  end

  @doc "Drop it."
  @spec down() :: :ok
  def down, do: execute("DROP TABLE #{@table}")
end
