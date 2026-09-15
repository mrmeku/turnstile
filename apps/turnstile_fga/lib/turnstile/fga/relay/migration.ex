defmodule Turnstile.Fga.Relay.Migration do
  @moduledoc """
  The cursor table, for an application's own migration to create. This
  package ships no migration files; each application has one that calls
  these.

      defmodule MyApp.Repo.Migrations.Relay do
        use Ecto.Migration

        def up, do: Turnstile.Fga.Relay.Migration.cursor_up()

        def down, do: Turnstile.Fga.Relay.Migration.cursor_down()
      end

  `cursor_up/1` creates `turnstile_relay_cursor(name text primary key,
  position bigint not null)` and grants the application role select, insert,
  and update: a runner connects as the application, and advancing a cursor
  replaces the position of a row that is already there. No delete is
  granted, because a runner is forgotten by dropping its row from a
  migration rather than at run time.

  The table a job reads its rows from is the application's own, and no
  helper here writes it: what a row holds is the job's.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration]

  import Ecto.Migration

  @table :turnstile_relay_cursor

  @schema NimbleOptions.new!(
            app_role: [
              type: :string,
              default: "turnstile_app",
              doc: "The database role the application connects as, which receives the grants."
            ]
          )

  @doc "Create the cursor table and its grants. Options: #{NimbleOptions.docs(@schema)}"
  @spec cursor_up(keyword()) :: :ok
  def cursor_up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)

    create table(@table, primary_key: false) do
      add(:name, :text, primary_key: true)
      add(:position, :bigint, null: false)
    end

    execute("GRANT SELECT, INSERT, UPDATE ON #{@table} TO #{options[:app_role]}")
    :ok
  end

  @doc "Drop the cursor table."
  @spec cursor_down() :: :ok
  def cursor_down do
    drop(table(@table))
    :ok
  end
end
