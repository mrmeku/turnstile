# Conformance

*The tests every adapter must pass, and the tests every mediated repo must pass. Tier 1 is the contract; `docs/requirements.md` says which requirement line each law answers.*

## 1. What conformance is

An adapter is conformant when `Turnstile.Conformance.AdapterCase` passes against its real engine over a population it did not write. The laws below are named by a requirement id and one sentence, and each is a test whose name is that sentence. Every adapter in this repository runs them in its own `mix test`; an adapter outside it runs them the same way (§6). No law is skipped silently: a law an adapter cannot run prints its reason.

A repo is conformant when `Turnstile.Conformance.RepoCase` passes against it: its exports are the surface the seam classifies, every non-plumbing call without a decision is refused, and the guarantees E1 to E5 hold.

## 2. The laws

Frozen: `Turnstile.Conformance.Law.all/0` holds this table as data, and the freeze test in `turnstile` holds the module to this document row for row. Bodies are in `Turnstile.Conformance.AdapterCase.Laws` and its modules: `Accounts` for the `ac2` and `ac6` laws, `Audit` for the `au` laws, `Versions` for the `cm3` laws, and the module itself for the `ac3` laws and the helpers they share.

| Id | Sentence | Controls |
|---|---|---|
| `ac2-01` | A single-row insert, update, or delete of an account through the seam emits one change event naming the deciding subject, the target, and the clearance before and after | AC-2, AC-2(4) |
| `ac2-02` | A grant that expires one second after the port's clock allows and one that expired one second before denies, by the configured clock and not the database's | AC-2(2), AC-2(3) |
| `ac2-03` | A subject whose account no longer satisfies the rule is denied at the next check with no other change | AC-2(3), PS-5 |
| `ac2-04` | Review returns, for every subject including a privileged one, a rule that lists exactly the objects check allows, with one decision per subject and one for the reviewer under one operation id | AC-2(7), AC-6(7) |
| `ac2-05` | After a grant is revoked the next check denies, and the latency from revocation to denial is printed and never asserted | AC-2(13), PS-4 |
| `ac3-01` | check agrees with the world's own rule for every subject, operation, and object drawn | AC-3 |
| `ac3-02` | An ungranted object, an unknown operation, an unknown subject, and an unknown subject kind are denied, the last before the adapter is called | AC-3 |
| `ac3-03` | scope returns exactly the rows check allows, for the scoped schema and for the schema its decision carries | AC-3 |
| `ac3-04` | scope over a thousand rows is one decision and one query beyond setup | AC-3 |
| `ac3-05` | An unreachable decider denies and emits one decision event carrying the exception | AC-3 |
| `ac6-01` | A user holding a grant is allowed, and the privileged subject of the same account is denied the same object | AC-6(2) |
| `au2-01` | Every authorize and check emits exactly one decision event carrying subject, kind, operation, object, verdict, reason, version, operation id, and time | AU-2, AC-6(9) |
| `au2-02` | A denial's decision event carries the reason for it | AU-2 |
| `au2-03` | scope and review emit decisions whose verdict is scoped | AU-2 |
| `au3-01` | No value in a decision event equals an attribute value of the world | AU-3 |
| `au3-02` | A change event carries operation, kind, target, actor, time, operation id, and the old and new value of every fact column that changed | AU-3 |
| `au3-03` | An access event carries object type, ids, decision id, subject, operation id, and time | AU-3 |
| `au3-04` | Within one operation id the decision, change, and access events each carry it | AU-3(1) |
| `au12-01` | A single-row write to an audited schema emits its change event inside the write's transaction | AU-12, AC-2(4) |
| `au12-02` | A bulk write to an audited schema raises and changes nothing | AU-12 |
| `au12-03` | A write that goes around the seam emits nothing | AU-12 |
| `au12-04` | A write the database refuses leaves no row and no event | AU-12 |
| `au12-05` | An unmediated read or write of a protected schema is refused | AU-12 |
| `au12-06` | Every mediated read of a protected schema emits one access event | AU-12 |
| `cm3-01` | Publishing a version emits the adapter's version event naming the author and the approval | CM-3, CM-5 |
| `cm3-02` | A decision reports the version it was taken under, before and after a new version is published | CM-3(2) |
| `cm3-03` | A tightened rule is a policy version whose event names the artifact it is on this adapter | CM-5(1) |
| `cm3-04` | After a rule is tightened the reader it excludes is denied, and the propagation latency is printed and never asserted | CM-3(2) |

**Beside the laws**, in the same template: the adapter declares its scope cap; a single-row fact write is the write alone and one change event; and `au12-07`, every column a rule reads is a declared fact, which is one coverage test per adapter package whose rules read columns (`Turnstile.Rbac.Coverage`, `Turnstile.Postgres.Coverage`, `Turnstile.Cerbos.Coverage`, each run by its thin application too) and the tuple mapping case for OpenFGA, whose declaration is the mapping itself. The Postgres checker reads the bound schemas, so a Postgres binding names every schema its policies read beside the ones they protect.

**Properties, shapes, and measurements.** `ac3-01`, `ac3-02`, and `ac3-03` are `stream_data` properties over populations `Turnstile.Conformance.Gen` draws from the world's generator. `ac3-04` and the fact-write shape count queries with `Turnstile.Test.queries/2` and events with `Turnstile.Test.changes/1`, so they are exact in the sandbox and cannot flap; an adapter that adds queries of its own to every call declares how many through `setup_queries:`. `ac2-05` and `cm3-04` write on the committed repo, read the monotonic clock, settle the adapter where it has state to settle, poll until the first denial with `Turnstile.Test.poll/2`, and print the total, its components, and the poll interval as the floor. Nothing in the suite fails on a latency number.

## 3. The world

`Turnstile.Conformance.World` is the behaviour through which the template reads a population without knowing its schemas. The neutral fixture that implements it in this repository, `Turnstile.Fixture`, lives in `turnstile`'s `test/support` and is not published: accounts with a clearance and a kind, folders, items under folders, and memberships, where a membership is a grant of a role on a folder to an account, with an expiry, and the rule is that a live membership of the right role, held by a subject of the right kind, allows the operation on the folder and on its items.

| Callback | What it answers |
|---|---|
| `schemas/0`, `scope_schema/0` | Every protected schema the properties scope over; the one the shape cases fill with rows |
| `operations/0` | The operations the rule knows |
| `exemption/0` | The exemption every write of a population declares through the seam |
| `object_of/1` | The object a grant on this thing covers |
| `generator/0` | A random population, for the properties |
| `granted/0`, `ungranted/0`, `scoped/0` | One subject, one object, one grant; the same without the grant; the same with more objects than the grant covers |
| `focus/1` | The subject the fixed worlds grant to, and what they grant it on |
| `subjects/1`, `objects/1` | Every subject, including one of kind `:privileged`, and every object the population knows |
| `allowed?/4` | The rule: what the population says about one subject, operation, and object |
| `facts/1` | The values the rule reads from the population, which no decision event may carry |
| `clear/1`, `insert/2`, `fill/3` | Delete every row through the seam one at a time; write the population; add rows to the scope schema |
| `insert_grant/5`, `revoke/4`, `disqualify/3` | Write one grant with attributes, of which the laws set `expires_at` and `mediation`, the `turnstile:` option the write carries in place of the exemption; take a grant away; change the account fact the rule reads |
| `module/1` | The module behind a population |

Each adapter package carries what the fixture needs on its own mechanism in its own `test/support`, under a `Conformance` module of the package's namespace: `turnstile_rbac` the role table and predicates, `turnstile_postgres` the row-level security migration for the fixture tables, `turnstile_cerbos` the attribute declarations, `turnstile_fga` the tuple mapping. What an engine reads as text stays under `priv/conformance/`: the Cerbos policies and the OpenFGA model. The example's domain appears in none of them.

## 4. Seed and versions

`Turnstile.Conformance.Seed` is for an adapter whose working state is not the tables: `seed/1` loads a world into the adapter's own state, and `outage/0` makes its engine unreachable for the fail-closed law. An adapter that reads the tables passes none.

`Turnstile.Conformance.Versions` is what the `cm3` laws need and a test cannot write without naming the adapter: `event/0`, the telemetry event the adapter publishes a policy version on; `tighten/0`, which publishes a version that excludes the granted reader; `restore/0`, which puts the original back; and the optional `setup/1`, for an engine that keeps state per test. Each adapter package carries its own under `test/support/turnstile/<adapter>/conformance/versions.ex`. An adapter that passes no `versions:` runs the `cm3` laws as skipped with the reason printed.

## 5. The repo case

`use Turnstile.Conformance.RepoCase, repo: MyApp.Repo` writes the tests itself. The repo answers `__turnstile__/1` and exports nothing outside the list in `core/surface.ex`, where an export outside the list fails with the function's name and arity. Every query, write, and raw function is called on a protected schema without a decision and asserted to raise `%Turnstile.Error{reason: :unmediated}` before any SQL. With a `rows:` module, the five guarantees:

| Id | Guarantee |
|---|---|
| E1 | A single-row write to an audited schema emits one change event, carrying every fact field that changed. |
| E2 | A bulk write to an audited schema raises and emits nothing. |
| E3 | A write that goes around the seam emits nothing. |
| E4 | A consumer that writes to the same repository from its handler joins the write transaction. |
| E5 | A mediated read of a protected schema emits one access event whose ids are the rows returned and whose decision id is the decision it ran under; `exists?` emits one with no ids; a read under an exemption emits nothing. |

The `rows:` module is a `Turnstile.Conformance.RepoCase.Rows`: `row/0`, an unwritten row of an audited schema; `change/1`, a change of a written row that sets a fact field; `mediation/0`, the `turnstile:` option those writes carry; `around/1`, the way this deployment changes the row without passing the seam; `protected/0`, an unwritten row of a schema that declares an object type; `decision/1`, a decision from `Turnstile.authorize/4` that admits reading it; and the optional `setup/1`, run first in every test with the test's tags.

## 6. Running the suite

Inside this repository, each adapter's test module is one `use`:

```elixir
use Turnstile.Conformance.AdapterCase,
  adapter: Turnstile.Postgres,
  repo: Turnstile.TestRepos.Sandboxed,
  world: Turnstile.Fixture.World,
  versions: Turnstile.Postgres.Conformance.Versions,
  committed: [repo: Turnstile.TestRepos.Committed, owner: Turnstile.TestRepos.Owner, tables: [...]]
```

`seed:` and `outage:` name a `Turnstile.Conformance.Seed`, `setup_queries:` the queries the adapter adds to every call, and `committed:` the repo the latency laws write on. The adapter binds through the configuration override, so all four adapters run in one `mix test` as async modules, and a test tagged `:committed` runs on the committed database and truncates through the owner repo.

An adapter outside this repository supplies its own `World`, its own repo, a Postgres of its own, and the artifacts its mechanism needs for that world. The template reads nothing else. `turnstile_dev` holds the ephemeral cluster this repository's suites start and is not published; an adopter's `test_helper.exs` starts whatever database it has.
