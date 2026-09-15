defmodule Turnstile.Fga.Migration do
  @moduledoc """
  The outbox table and the cursor table, for a thin application's own
  migration to create. This package ships no migration files; each thin
  application has one that calls these.

      defmodule ExampleFga.Repo.Migrations.Fga do
        use Ecto.Migration

        def up do
          :ok = Turnstile.Fga.Migration.outbox_up()
          Turnstile.Fga.Migration.cursor_up()
        end

        def down do
          :ok = Turnstile.Fga.Migration.cursor_down()
          Turnstile.Fga.Migration.outbox_down()
        end
      end

  `outbox_up/1` creates `turnstile_fga_outbox(id bigserial primary key,
  object text not null)` and grants the application role select, insert, and
  delete: the marker is written in the transaction that changed the rows,
  and the drain reads a batch and deletes what it delivered, both as the
  application. No update is granted, because a marker is written once and
  read as it was written.

  `cursor_up/1` creates `turnstile_relay_cursor(name text primary key,
  position bigint not null)`, where a `Turnstile.Fga.Relay` runner keeps its
  place, and grants the application role select, insert, and update: a
  runner connects as the application, and advancing a cursor replaces the
  position of a row that is already there. No delete is granted, because a
  runner is forgotten by dropping its row from a migration rather than at
  run time.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration]

  import Ecto.Migration

  @outbox :turnstile_fga_outbox
  @cursor :turnstile_relay_cursor

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

    create table(@outbox, primary_key: false) do
      add(:id, :bigserial, primary_key: true)
      add(:object, :text, null: false)
    end

    execute("GRANT SELECT, INSERT, DELETE ON #{@outbox} TO #{options[:app_role]}")
    execute("GRANT USAGE ON SEQUENCE #{@outbox}_id_seq TO #{options[:app_role]}")
    :ok
  end

  @doc "Drop the outbox table."
  @spec outbox_down() :: :ok
  def outbox_down do
    drop(table(@outbox))
    :ok
  end

  @doc "Create the cursor table and its grants. Options: #{NimbleOptions.docs(@schema)}"
  @spec cursor_up(keyword()) :: :ok
  def cursor_up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)

    create table(@cursor, primary_key: false) do
      add(:name, :text, primary_key: true)
      add(:position, :bigint, null: false)
    end

    execute("GRANT SELECT, INSERT, UPDATE ON #{@cursor} TO #{options[:app_role]}")
    :ok
  end

  @doc "Drop the cursor table."
  @spec cursor_down() :: :ok
  def cursor_down do
    drop(table(@cursor))
    :ok
  end
end
