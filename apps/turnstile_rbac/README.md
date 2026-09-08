# Turnstile RBAC in code

The adapter whose rules are Elixir modules: `Turnstile.Code`.

- `use Turnstile.Code.Policy`: the policy module. `role name, permissions` is one row of the role table, declared data. `object Schema do ... end` names a protected schema and its clauses: `grant name, RelationshipSchema` holds a role on a row through the relationship the schema declares with `Turnstile.Schema.relationship/1`, with `on:`, `role:`, or `as:` when the declaration is not enough; `predicate name, &Module.function/2` is a function of the subject and the environment that returns a `dynamic` over the row, or a boolean, and lives in the same modules as the table. An operation is allowed on a row when any grant holds a role that permits it and every predicate holds. `use` takes `version:`, `author:`, and `approval:`.
- `Turnstile.Code`: the `Turnstile.Adapter` implementation. `scope` returns the rule as one `dynamic` over subqueries and runs no query. `check`, `authorize`, `batch`, and `explain` run one query per object type that selects every clause for the rows asked about, so a reason names the grant that allowed or the predicate that failed, and `explain` lists every clause that held. A row that is not there, a subject no grant reaches, an operation no role permits, and a type the policy does not protect are denied with their reasons. The adapter takes no options; its configuration entry is the bare module.
- `Turnstile.Code.Binding`: the policy module and the mediated repo the rules read through. `bind/1` validates the pair once at boot beside the configuration's boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `Turnstile.Code.Version`: the policy version. Its identifier is the `version:` the policy gave, or the content hash, a digest of the policy module and every predicate module. `Turnstile.Code.publish/0` appends the version to the ledger at boot when the ledger's latest names an older one or none, inside the ledger's transaction when the ledger offers one; one event per version, never per boot or node. In ledger mode none it emits `[:turnstile, :code, :policy_version]` and appends nothing. The content is the role table and the module list as text under the configured cap, and a pointer to the modules otherwise.
- `Turnstile.Code.Coverage`: declared-fact coverage. `check/1` walks the `dynamic` every rule becomes, subqueries included, and fails with the schema and the column of any read that no `fact`, `relationship`, primary key, or carried foreign key declares. A fragment cannot be walked and is a finding of its own.
- `priv/conformance/`: the role table and the predicates that encode the neutral fixture's rule, the modules the conformance suite binds. The test run compiles them; an application never loads them.

`glossary.md` defines the words this package owns. The package's `lib` depends on `turnstile_core`, `ecto`, and `nimble_options`; `ecto_sql` and `postgrex` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## Binding at boot

After the configuration boots with `adapter: Turnstile.Code`, the application binds and publishes:

```elixir
{:ok, _binding} = Turnstile.Code.Binding.bind(policy: MyApp.Roles, repo: MyApp.Repo)
{:ok, _event} = Turnstile.Code.publish()
```
