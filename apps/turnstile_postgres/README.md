# Turnstile on row-level security

The adapter whose rules are Postgres policies on the tables themselves: `Turnstile.Postgres`. The database enforces them on every statement, including statements this library never sees, so the rules hold for a report tool, a console session, and a migration alike. The adapter takes no options; its configuration entry is the bare module.

- `Turnstile.Postgres`: the `Turnstile.Adapter` implementation. `around_query/3` sets the session settings for the length of the call. `check`, `authorize`, and `batch` run one statement per object type under those settings, where a row the operation's `SELECT` policy does not admit is a denial and the operation's `UPDATE` gate, where it has one, is read in the same statement. `scope` runs no statement and answers the rule `true`, because the policy narrows the query when the repo runs it. `explain` answers the verdict and names nothing further, because the database does not report which policy admitted a row. The replica-lag component of revocation latency is reported "not measured", because every statement goes to the primary.
- `Turnstile.Postgres.Binding`: the mediated repo, the schemas whose tables the policies protect and read, and the table whose highest version is the policy version. `bind/1` validates them once at boot beside the configuration's boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `Turnstile.Postgres.Settings`: what a policy reads. Four settings are always set, `turnstile.subject_id`, `turnstile.subject_kind`, `turnstile.operation`, and `turnstile.now`, and every fact the caller supplied is set under its own name, so an application whose policies read `current_setting('turnstile.reauthenticated_at', true)` supplies `reauthenticated_at` as a fact and this package never learns the name. A name nobody supplied is unset, and an absent fact denies. They render as one `SELECT` over `set_config(name, value, true)`, which is one statement, one round trip, and one query in the shape counts. Their SHA-256 is what a scope decision carries as the rule of its reason, because under row-level security the settings are what the database enforced.
- `Turnstile.Postgres.Session`: where the settings meet the connection. `set_config(name, value, true)` is local to a transaction, so a call that is not already inside one opens a transaction for its own length and the settings leave with it, and two subjects in one transaction each set their own.
- `Turnstile.Postgres.Catalog`: what the database says its own rules are, read from `pg_policy` for the policies, `pg_depend` for the columns they reference, and the migrations table for the version. It is read once per binding and kept, so no call on the request path pays for it.
- `Turnstile.Postgres.Policy` and `Turnstile.Postgres.Name`: one policy as `pg_policy` holds it, and the check every identifier passes before it reaches a statement, since a name cannot be a parameter.
- `Turnstile.Postgres.Migration`: the helpers a migration calls, and the only place this package writes DDL. They turn row-level security on and force it on the table's owner too, write the `SELECT` policy of an operation under its operation guard, write the `UPDATE` gate of an operation without one, add the permissive `true` policy a command needs under forced row-level security, grant a role the privileges that let it reach a table at all, and read the policies back to append the policy version in the same transaction as the DDL.
- `Turnstile.Postgres.Version`: the policy version is the migration number, and the content is the policies as `pg_policy` renders them, carried by value under the configured cap and left as a pointer to the tables above it. In ledger mode none the append emits `[:turnstile, :postgres, :policy_version]` and records nothing.
- `Turnstile.Postgres.Coverage`: declared-fact coverage. It reads the policy expressions from `pg_policy` and the columns they reference from `pg_depend`, and fails with the column's name on a read that no `fact`, `relationship`, primary key, or carried foreign key declares, and with the table's name on a read of a table no bound schema names.
- `priv/conformance/`: the row-level security migration for the neutral fixture, the rules the conformance suite runs against. The test run compiles it; an application never loads it.

`glossary.md` defines the words this package owns. The package's `lib` depends on `turnstile_core`, `ecto`, and `nimble_options`; `ecto_sql` and `postgrex` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## Two policies per operation, and what each is for

The scope policy of an operation carries the guard `current_setting('turnstile.operation', true) = '<operation>'`. Permissive policies combine with OR, so without the guard the policy of one operation would widen another; with it, only the policy of the operation in force can hold.

The gate policy of an operation carries no guard. It is an `UPDATE` policy, and its `WITH CHECK` expression is what the database applies to a write whether or not anything asked first, which is the write gate that needs no application code. `check` reads its `USING` expression in the same statement that answers visibility, so an answer given before a write agrees with what the write meets.

## Binding at boot

After the configuration boots with `adapter: Turnstile.Postgres`, the application binds:

```elixir
{:ok, _binding} = Turnstile.Postgres.Binding.bind(repo: MyApp.Repo, schemas: [MyApp.Document, MyApp.Membership])
```

The catalog is read once per binding on first use. An application that would rather pay for that read at boot than on the first call reads it there, after the binding.

The application's role must not own the protected tables and must carry `NOBYPASSRLS`, since a table's owner and a role with `BYPASSRLS` are not subject to the policies. Forcing row-level security closes the first of those for the owner; the second is the role's own definition.
