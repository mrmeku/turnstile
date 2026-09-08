defmodule Turnstile.Ledger.Migration do
  @moduledoc """
  Migration helpers a thin application calls from its own migrations. The
  library ships no migration files; each thin application has one set that
  calls these.

      defmodule ExampleRbac.Repo.Migrations.Counter do
        use Ecto.Migration
        def up, do: Turnstile.Ledger.Migration.counter_up()
        def down, do: Turnstile.Ledger.Migration.counter_down()
      end

  `counter_up/1` creates `turnstile_ledger_counter(name text primary key,
  position bigint not null)`, inserts the `default` row at 0, and grants the
  application role select, insert, and update on it: the row is locked and
  advanced by every fact-writing transaction, and the application role, not
  the owner, is what those transactions run as.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration]

  import Ecto.Migration

  @table :turnstile_ledger_counter

  @schema NimbleOptions.new!(
            app_role: [
              type: :string,
              default: "turnstile_app",
              doc: "The database role the application connects as, which receives the grants."
            ]
          )

  @doc "Create the counter table, its `default` row, and the grants. Options: #{NimbleOptions.docs(@schema)}"
  @spec counter_up(keyword()) :: :ok
  def counter_up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @schema)

    create table(@table, primary_key: false) do
      add :name, :text, primary_key: true
      add :position, :bigint, null: false
    end

    execute "INSERT INTO #{@table} (name, position) VALUES ('default', 0)"
    execute "GRANT SELECT, INSERT, UPDATE ON #{@table} TO #{options[:app_role]}"
    :ok
  end

  @doc "Drop the counter table."
  @spec counter_down() :: :ok
  def counter_down do
    drop table(@table)
    :ok
  end
end
