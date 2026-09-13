# Row-level security glossary

The words `turnstile_postgres` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Policy | One row-level security rule as `pg_policy` holds it: a name, a table, the command it applies to, and its `USING` and `WITH CHECK` expressions |
| Scope policy | The `SELECT` policy of one operation, named `turnstile_scope_<operation>`: the rows that operation may see |
| Gate policy | The `UPDATE` policy of one operation, named `turnstile_gate_<operation>`: the expression an answer reads before a write and the expression the database applies to the write |
| Operation guard | The clause `current_setting('turnstile.operation', true) = '<operation>'` that a scope policy carries and a gate policy does not, so the policy of one operation cannot widen another |
| Predicate | The `USING` or `WITH CHECK` expression of a policy, written by whoever writes the migration and reaching the database as given |
| Session setting | A name and a text value set with `set_config(name, value, true)` for the length of a call, which a policy reads with `current_setting(name, true)` |
| Settings hash | The SHA-256 of the settings a call ran under, carried as the rule of a scope decision's reason |
| Catalog | The policies of the bound tables, the columns they reference, and the version, as the database reports them; read once per binding |
| Binding | The mediated repo, the protected schemas, and the migrations table, bound once at boot or overridden per process |
| Protect | Turn row-level security on for a table and force it, so the policies apply to the table's owner as well as to everyone else |
| Admit | The permissive `true` policy of one command, which a table whose rows are written outside a decision needs under forced row-level security |
| Migration number | The highest version in the migrations table, which is the policy version a decision names |
| Coverage | The read of the policy expressions and their column references that fails on a column no declaration names |
| Finding | One undeclared read: a schema and a column, or a table no bound schema names |
