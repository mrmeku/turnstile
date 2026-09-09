# Ledger glossary

The words `turnstile_ledger` owns.

| Term | Meaning |
|---|---|
| Event / ledger / fold / replay | An immutable record of a change / an append-only list of them / reducing them to state / folding up to a date |
| Transactional outbox | A record committed in the same transaction as the write it describes and read afterwards by consumers from the same database; the ledger's shape, never emptied |
| Ledger position / head / applied position | The index in the ledger / the counter row's committed value / the position an adapter's state has applied |
| Counter row | The locked row every fact-writing transaction takes positions from; `default` in production, one row per test in the sandbox |
| Take | Advancing the counter row by the number of events an append holds and stamping them over the range it answers with; one statement on Postgres |
| Bulk write | One transaction that writes many facts and appends their events: `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, `bulk_insert/3`, what an application uses where a plain `Repo.update_all` on a fact field is refused |
| Difference condition | The null-safe `WHERE` that narrows a bulk write to the rows whose value would change, so a write of the value a row already holds touches nothing |
| Tagged value | A fact value as a column holds it: the term with its type beside it, so what comes back is what was written |
| Lock clause | The clause a fact row is re-read under inside the writing transaction, `FOR UPDATE` on Postgres |
| Genesis | The backfill that gives an existing application's ledger an origin |
| Origin | The events at position zero, which the backfill wrote: read on its own, because a read answers what lies above a position and zero is the lowest there is |
| Append-only grant | What the events migration grants the application role: insert an event and read one, and no way to change or remove one |
| Catalog check / cascade | Reading the database catalog for a foreign key into a fact schema's table with `ON DELETE CASCADE` or `ON DELETE SET NULL`, which would delete or blank a fact with no event to say so / such a key, refused |
| Drift / reconcile | Facts changed outside the seam / checking the tables against the ledger on an interval |
| Point-in-time review | A review of a date the ledger covers, as against a review of today |
| Dialect | The behaviour behind the ledger's database-dependent mechanisms; Postgres ships |
| Schema dump | `pg_dump --schema-only` of the schema an application's migrations produce, committed under `priv/schema/` and diffed in CI |
