defmodule Turnstile.Fga.Migration do
  @moduledoc """
  The checkpoint table, for a thin application's own migration to create.
  This package ships no migration files; each thin application has one that
  calls these.

      defmodule ExampleFga.Repo.Migrations.Fga do
        use Ecto.Migration

        def up, do: Turnstile.Fga.Migration.checkpoint_up()

        def down, do: Turnstile.Fga.Migration.checkpoint_down()
      end

  `checkpoint_up/1` creates `turnstile_fga_checkpoint(store text primary key,
  position bigint not null)` and grants the application role select, insert,
  and update: the projector runs as the application, and advancing a
  checkpoint replaces the position of a row that is already there. No delete
  is granted, because a store is forgotten by dropping its row from a
  migration rather than at run time.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration]

  import Ecto.Migration

  @table :turnstile_fga_checkpoint

  @schema NimbleOptions.new!(
            app_role: [
              type: :string,
              default: "turnstile_app",
              doc: "The database role the application connects as, which receives the grants."
            ]
          )

  @doc "Create the checkpoint table and its grants. Options: #{NimbleOptions.docs(@schema)}"
  @spec checkpoint_up(keyword()) :: :ok
  def checkpoint_up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)

    create table(@table, primary_key: false) do
      add(:store, :text, primary_key: true)
      add(:position, :bigint, null: false)
    end

    execute("GRANT SELECT, INSERT, UPDATE ON #{@table} TO #{options[:app_role]}")
    :ok
  end

  @doc "Drop the checkpoint table."
  @spec checkpoint_down() :: :ok
  def checkpoint_down do
    drop(table(@table))
    :ok
  end
end
