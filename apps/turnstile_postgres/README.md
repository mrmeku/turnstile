# Turnstile on row-level security

The adapter whose rules are Postgres policies on the tables themselves: `Turnstile.Postgres`. The database enforces them on every statement, including statements this library never sees, so the rules hold for a report tool, a console session, and a migration alike. A migration is a policy version, revocation is one commit, and the boundary cost is nothing new. The adapter takes no options; its configuration entry is the bare module.

- `Turnstile.Postgres`: the `Turnstile.Adapter` implementation. `around_query/3` sets the session settings for the length of the call, `turnstile.subject_id`, `turnstile.subject_kind`, `turnstile.operation`, `turnstile.now`, and one name per fact the caller supplied, so an application whose policies read `current_setting('turnstile.reauthenticated_at', true)` supplies `reauthenticated_at` as a fact and this package never learns the name. A name nobody supplied is unset, and an absent fact denies. They are set by one `SELECT` over `set_config(name, value, true)`, one statement and one query in the shape counts; `set_config` is local to a transaction, so a call not already inside one opens a transaction for its own length and the settings leave with it, and two subjects in one transaction each set their own. `decide` runs one statement under those settings, where a row the operation's `SELECT` policy does not admit is a denial and the operation's `UPDATE` gate, where it has one, is read in the same statement. `scope` runs no statement and answers the rule `true`, because the policy narrows the query when the repo runs it, and its reason carries the SHA-256 of the settings the database will read, because under row-level security the settings are what it enforced. The scope cap is `:none`.
- `Turnstile.Postgres.Binding`: the mediated repo, the schemas whose tables the policies protect and read, and the table whose highest version is the policy version. `bind/1` validates them once at boot beside the configuration's boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `Turnstile.Postgres.Catalog`: what the database says its own rules are, read from `pg_policy` for the policies, `pg_depend` for the columns they reference, and the migrations table for the version. It is read once per binding and kept, so no call on the request path pays for it.
- `Turnstile.Postgres.Policy`: one policy as `pg_policy` holds it. Every identifier this package puts into a statement is checked first, a plain lowercase name within the length an identifier can hold, since a name cannot be a parameter.
- `Turnstile.Postgres.Migration`: the helpers a migration calls, and the only place this package writes DDL. They turn row-level security on and force it on the table's owner too, write the `SELECT` policy of an operation under its operation guard, write the `UPDATE` gate of an operation without one, add the permissive `true` policy a command needs under forced row-level security, grant a role the privileges that let it reach a table at all, and read the policies back to append the policy version in the same transaction as the DDL.
- `Turnstile.Postgres.Version`: the policy version is the migration number, and the content is the policies as `pg_policy` renders them, carried by value under the configured cap and left as a pointer to the tables above it. Publishing emits `[:turnstile, :postgres, :policy_version]` carrying the version, once per call, and records nothing.
- `Turnstile.Postgres.Coverage`: declared-fact coverage. It reads the policy expressions from `pg_policy` and the columns they reference from `pg_depend`, and fails with the column's name on a read that no `fact`, `relationship`, primary key, or carried foreign key declares, and with the table's name on a read of a table no bound schema names.
- Test support, compiled and never published: the row-level security migration for the neutral fixture and the versions module that tightens and restores one of its policies, which the conformance suite runs against.

The package's `lib` depends on `turnstile`, `ecto`, and `nimble_options`; `ecto_sql` and `postgrex` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## Mechanism per rule shape

| Rule shape | Mechanism |
|---|---|
| Who may see a row under an operation | the scope policy, a `SELECT` policy named `turnstile_scope_<operation>` carrying the guard `current_setting('turnstile.operation', true) = '<operation>'`; permissive policies combine with OR, so without the guard the policy of one operation would widen another |
| A write gate | the gate policy, an `UPDATE` policy named `turnstile_gate_<operation>` with no guard, whose `WITH CHECK` the database applies to a write whether or not anything asked first; `decide` reads its `USING` in the same statement that answers visibility, so an answer given before a write agrees with what the write meets |
| A test on the subject or the moment | a session setting the adapter binds inside `around_query/3`, read with `current_setting(name, true)` |
| A rule over a whole type | the scope policy itself; `scope` answers `true` and the database narrows the query |
| A row written outside a decision | the permissive `true` policy of that command, which a table whose rows are written under an exemption needs under forced row-level security |

The application's role must not own the protected tables and must carry `NOBYPASSRLS`, since a table's owner and a role with `BYPASSRLS` are not subject to the policies. Forcing row-level security closes the first of those for the owner; the second is the role's own definition.

## Latency

Revocation latency has one component, commit: every statement goes to the primary, so replica lag is reported as not measured. A rule change propagates with the migration that carries it, in the same transaction as its DDL. The conformance suite prints both measurements beside its run and asserts nothing about them.

## Binding at boot

After the configuration boots with `adapter: Turnstile.Postgres`, the application binds:

```elixir
{:ok, _binding} = Turnstile.Postgres.Binding.bind(repo: MyApp.Repo, schemas: [MyApp.Document, MyApp.Membership])
```

The catalog is read once per binding on first use. An application that would rather pay for that read at boot than on the first call reads it there, after the binding.
