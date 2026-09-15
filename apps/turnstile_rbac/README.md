# Turnstile RBAC in code

The adapter whose rules are Elixir modules: `Turnstile.Rbac`. A deploy is a policy version, revocation is one commit, and the boundary cost is none, because nothing runs beside the application. The adapter takes no options; its configuration entry is the bare module.

- `use Turnstile.Rbac.Policy`: the policy module. `role name, permissions` is one row of the role table, declared data. `object Schema do ... end` names a protected schema and its clauses. `grant name, RelationshipSchema` holds a role on a row through the relationship the schema declares with `Turnstile.Schema.relationship/1`, with `on:`, `role:`, or `as:` when the declaration is not enough, and `through:` when the relationship names a row the protected row points at rather than the protected row itself: a list of hops from the protected row outward, each `{Schema, column}` or `{Schema, column, where: &Module.function/0}`. `predicate name, &Module.function/2` is a function of the subject and the environment that returns a `dynamic` over the row, or a boolean, with `only: [operations]` when it applies to some operations and not others. An operation is allowed on a row when any grant holds a role that permits it and every predicate that applies to the operation holds. `use` takes `version:`, `author:`, and `approval:`.
- `Turnstile.Rbac`: the `Turnstile.Adapter` implementation. `decide` runs one query per object type that selects every clause for the row asked about, so a reason names the grant that allowed or the predicate that failed. A row that is not there, a subject no grant reaches, an operation no role permits, and a type the policy does not protect are denied with their reasons. `scope` returns the rule as one `dynamic` over subqueries and runs no query. The scope cap is `:none`.
- `Turnstile.Rbac.Binding`: the policy module and the mediated repo the rules read through. `bind/1` validates the pair once at boot beside the configuration's boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `Turnstile.Rbac.Version`: the policy version. Its identifier is the `version:` the policy gave, or the content hash, a digest of the policy module and every module a predicate or a hop filter lives in. `Turnstile.Rbac.publish/0` emits the version at boot as `[:turnstile, :rbac, :policy_version]`, once per call, and stores nothing. The content is the role table and the module list as text under the configured cap, and a pointer to the modules otherwise.
- `Turnstile.Rbac.Coverage`: declared-fact coverage. `check/1` walks the `dynamic` every rule becomes, subqueries included, and fails with the schema and the column of any read that no `fact`, `relationship`, primary key, or carried foreign key declares. A fragment cannot be walked and is a finding of its own.
- Test support, compiled and never published: the role table, the predicates, and the versions module that encode the neutral fixture's rule, which the conformance suite binds.

The package's `lib` depends on `turnstile`, `ecto`, and `nimble_options`; `ecto_sql` and `postgrex` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## Mechanism per rule shape

| Rule shape | Mechanism |
|---|---|
| A role held on a row | a grant through the relationship schema; `through:` where the relationship is one or more hops away |
| A test on the subject or the row | a predicate returning a `dynamic`, read at the call from the environment the port stamped |
| A rule over a whole type | the same clauses composed into the `dynamic` that `scope` returns, so a scoped query and a checked row agree |
| A write gate | the role table alone; the write itself is refused by the seam without a decision for the operation |

## Latency

Revocation latency has one component, commit: a revoking write is visible to the next query. The conformance suite prints the measurement beside its run and asserts nothing about it.

## Binding at boot

After the configuration boots with `adapter: Turnstile.Rbac`, the application binds and publishes:

```elixir
{:ok, _binding} = Turnstile.Rbac.Binding.bind(policy: MyApp.Roles, repo: MyApp.Repo)
{:ok, _event} = Turnstile.Rbac.publish()
```
