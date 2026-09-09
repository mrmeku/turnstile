defmodule Turnstile.Ledger.Migration do
  @moduledoc """
  Migration helpers a thin application calls from its own migrations. The
  library ships no migration files; each thin application has one set that
  calls these.

      defmodule ExampleRbac.Repo.Migrations.Ledger do
        use Ecto.Migration
        def up do
          Turnstile.Ledger.Migration.counter_up()
          Turnstile.Ledger.Migration.events_up()
        end

        def down do
          Turnstile.Ledger.Migration.events_down()
          Turnstile.Ledger.Migration.counter_down()
        end
      end

  `events_up/1` creates `turnstile_ledger_events`, its two indexes, and the
  append-only grant: the application role may add an event and read one, and
  has no way to change or remove one, which is what makes the table a record
  rather than a cache. The position is indexed and not unique, because
  genesis writes every current fact at position zero.

  `counter_up/1` creates `turnstile_ledger_counter(name text primary key,
  position bigint not null)`, inserts the `default` row at 0, and grants the
  application role select, insert, and update on it: the row is locked and
  advanced by every fact-writing transaction, and the application role, not
  the owner, is what those transactions run as.
  """

  use Boundary, top_level?: true, deps: [Ecto.Migration, Turnstile.Ledger.Dialect]

  import Ecto.Migration

  @table :turnstile_ledger_counter
  @events :turnstile_ledger_events

  @schema NimbleOptions.new!(
            app_role: [
              type: :string,
              default: "turnstile_app",
              doc: "The database role the application connects as, which receives the grants."
            ]
          )

  @events_schema NimbleOptions.new!(
                   app_role: [
                     type: :string,
                     default: "turnstile_app",
                     doc: "The database role the application connects as, which receives the grants."
                   ],
                   dialect: [
                     type: :atom,
                     doc:
                       "The dialect whose append-only grant is used. " <>
                         "The Postgres one answers when the options name none, and the name is read when the " <>
                         "migration runs, so this module compiles without it."
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

  @doc "Create the events table, its indexes, and the append-only grant. Options: #{NimbleOptions.docs(@events_schema)}"
  @spec events_up(keyword()) :: :ok
  def events_up(options \\ []) when is_list(options) do
    options = NimbleOptions.validate!(options, @events_schema)

    create table(@events) do
      add :position, :bigint, null: false
      add :kind, :text, null: false
      add :subject_ref, :map
      add :object_ref, :map
      add :attribute, :text
      add :old, :map
      add :new, :map
      add :operation_id, :text, null: false
      add :at, :timestamptz, null: false
      add :by, :map, null: false
    end

    create index(@events, [:position])
    create index(@events, [:operation_id])
    dialect = Keyword.get(options, :dialect, Turnstile.Ledger.Dialect.Postgres)
    grants = dialect.append_only_grant(to_string(@events), options[:app_role])
    Enum.each(grants, &execute/1)
    :ok
  end

  @doc "Drop the events table."
  @spec events_down() :: :ok
  def events_down do
    drop table(@events)
    :ok
  end

  @doc "Drop the counter table."
  @spec counter_down() :: :ok
  def counter_down do
    drop table(@table)
    :ok
  end
end
