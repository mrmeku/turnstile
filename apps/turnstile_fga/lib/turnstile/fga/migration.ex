defmodule Turnstile.Fga.Migration do
  @moduledoc """
  The outbox table, for a thin application's own migration to create. This
  package ships no migration files; each thin application has one that calls
  these.

      defmodule ExampleFga.Repo.Migrations.Fga do
        use Ecto.Migration

        def up, do: Turnstile.Fga.Migration.outbox_up()

        def down, do: Turnstile.Fga.Migration.outbox_down()
      end

  `outbox_up/1` creates `turnstile_fga_outbox(id bigserial primary key,
  object text not null)` and grants the application role select, insert, and
  delete: the marker is written in the transaction that changed the rows,
  and the drain reads a batch and deletes what it delivered, both as the
  application. No update is granted, because a marker is written once and
  read as it was written.

  A thin application creates the cursor table beside this one, with
  `Turnstile.Relay.Migration.cursor_up/1`, since the drain is a relay
  runner and the cursor is where it keeps its place.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration]

  import Ecto.Migration

  @table :turnstile_fga_outbox

  @schema NimbleOptions.new!(
            app_role: [
              type: :string,
              default: "turnstile_app",
              doc: "The database role the application connects as, which receives the grants."
            ]
          )

  @doc "Create the outbox table and its grants. Options: #{NimbleOptions.docs(@schema)}"
  @spec outbox_up(keyword()) :: :ok
  def outbox_up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)

    create table(@table, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:object, :text, null: false)
    end

    execute("GRANT SELECT, INSERT, DELETE ON #{@table} TO #{options[:app_role]}")
    execute("GRANT USAGE ON SEQUENCE #{@table}_id_seq TO #{options[:app_role]}")
    :ok
  end

  @doc "Drop the outbox table."
  @spec outbox_down() :: :ok
  def outbox_down do
    drop(table(@table))
    :ok
  end
end
