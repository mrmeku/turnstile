# Turnstile ledger

The Ecto ledger: what a thin application needs in its database to record every fact change and take positions for them.

At this stage it holds two things. `Turnstile.Ledger.Migration` is the migration helper a thin application's own migrations call to create the counter table, `turnstile_ledger_counter(name, position)`, with its `default` row at 0 and the application role's grants. `mix turnstile.schema_dump` runs an application's migrations on an ephemeral cluster as the owner role and writes `pg_dump --schema-only` to a file the application commits under `priv/schema/`, so `git diff --exit-code` proves the migrations produce the schema the repository shows.

The ledger itself, the events table, genesis, drift, and replay arrive with the stages `docs/delivery.md` lists. `glossary.md` defines the words this package owns.
