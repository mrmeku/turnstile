# Ledger glossary

The words `turnstile_ledger` owns.

| Term | Meaning |
|---|---|
| Event / ledger / fold / replay | An immutable record of a change / an append-only list of them / reducing them to state / folding up to a date |
| Transactional outbox | A record committed in the same transaction as the write it describes and read afterwards by consumers from the same database; the ledger's shape, never emptied |
| Ledger position / head / applied position | The index in the ledger / the counter row's committed value / the position an adapter's state has applied |
| Counter row | The locked row every fact-writing transaction takes positions from; `default` in production, one row per test in the sandbox |
| Genesis | The backfill that gives an existing application's ledger an origin |
| Drift / reconcile | Facts changed outside the seam / checking the tables against the ledger on an interval |
| Dialect | The behaviour behind the ledger's database-dependent mechanisms; Postgres ships |
| Schema dump | `pg_dump --schema-only` of the schema an application's migrations produce, committed under `priv/schema/` and diffed in CI |
