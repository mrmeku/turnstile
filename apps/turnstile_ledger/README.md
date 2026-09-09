# Turnstile ledger

The ledger as a table in the application's own database: every fact change recorded in the transaction that made it, with a position that orders the record.

- `Turnstile.Ledger.Ecto`: the `Turnstile.Ledger` implementation. An append takes as many positions as it has events from the counter row in one statement, stamps them, and inserts the rows in the transaction the write is already in, so a fact and the events that describe it commit together or not at all. A read is `position > from` in position order; the head is the counter row's committed value; the genesis backfill sits at position zero and `origin/1` reads it. The configuration entry is `{Turnstile.Ledger.Ecto, repo: MyApp.Repo, owner_repo: MyApp.OwnerRepo}`, and `Turnstile.Ledger.Ecto.Value` is the codec that tags a fact value so it reads back as the term that was written.
- `Turnstile.Facts`: `bulk_update/3`, `bulk_delete/2`, and `bulk_insert/3`, what an application writes many facts with, since a plain `Repo.update_all` on a fact field is refused when a ledger is configured. Each is one transaction, one audit record on `[:turnstile, :bulk, :start | :stop | :exception]`, and one append; a null-safe difference condition means a write to the value a row already holds touches nothing.
- `Turnstile.Ledger.Migration`: the helpers a thin application's own migrations call. `counter_up/1` creates `turnstile_ledger_counter(name, position)` with its `default` row at 0; `events_up/1` creates `turnstile_ledger_events`, its two indexes, and the append-only grant, which lets the application role add an event and read one and gives it no way to change or remove one.
- `Turnstile.Ledger.Genesis`: the backfill that gives an existing application's ledger an origin. Every current fact becomes an event at position zero, stamped "backfilled from tables on ⟨date⟩ by ⟨migration⟩" as its operation id, written through the owner-role repo. It runs the catalog check first, refuses to run twice, and is called from the migration that creates the events table.
- `Turnstile.Ledger.Catalog`: the check that a foreign key with `ON DELETE CASCADE` or `ON DELETE SET NULL` into a fact schema's table is refused, because the database would remove a grant or blank the column naming its subject with no event to say so.
- `Turnstile.Ledger.Reconcile` and `Turnstile.Ledger.Reconcile.Scheduler`: the ledger's fold against the facts the tables hold, both read through the owner-role repo on one connection, answering `Turnstile.Projection.Drift`. The scheduler runs a pass on an interval and emits `[:turnstile, :ledger, :reconcile]` with the sizes as measurements and the drift as metadata; the interval is the window inside which drift from outside the seam is found.
- `Turnstile.Ledger.Reader` and `Turnstile.Ledger.Replay`: paging every event of a ledger, the origin first, and state at a position or a date with the policy version in force there, which is what reproduces a decision months later.
- `Turnstile.Ledger.Dialect` and `Turnstile.Ledger.Dialect.Postgres`: the database-dependent mechanisms behind all of it. Postgres takes positions with one `UPDATE turnstile_ledger_counter SET position = position + $2 WHERE name = $1 RETURNING position`, locks a fact row for its re-read with `FOR UPDATE`, inserts events in batches of two thousand, and reads the catalog for cascades.
- `Turnstile.Ledger.Review` and `mix turnstile.review`: who can do what, as a table. The library owns the columns; the application names the module that answers the rows in its `mix.exs`, `turnstile: [review: [reporter: MyApp.Review]]`. The task reviews today, and reviewing a date the ledger covers is what point-in-time review adds.
- `mix turnstile.schema_dump`: an application's migrations run on an ephemeral cluster as the owner role, `pg_dump --schema-only` written to a file the application commits under `priv/schema/`, so `git diff --exit-code` proves the migrations produce the schema the repository shows.

`glossary.md` defines the words this package owns. The package's `lib` depends on `turnstile_core`, `ecto`, and `nimble_options`; `ecto_sql` and `postgrex` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## What the migrations do

Two migrations, in this order, in the thin application:

```elixir
defmodule MyApp.Repo.Migrations.Ledger do
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

defmodule MyApp.Repo.Migrations.Genesis do
  use Ecto.Migration

  def up do
    {:ok, _count} =
      Turnstile.Ledger.Genesis.run(
        [repo: MyApp.Repo, owner_repo: MyApp.OwnerRepo],
        [MyApp.Membership, MyApp.Account],
        migration: __MODULE__
      )
  end

  def down, do: :ok
end
```
