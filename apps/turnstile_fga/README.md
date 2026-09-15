# Turnstile on OpenFGA

The adapter whose working state is a relationship graph in a store of its own: `Turnstile.Fga`. The server is OpenFGA 1.19.0, pinned in the flake (`docs/contributing.md` §1), self-hosted with a datastore of its own. Facts become tuples in a store, rules become a model that is immutable and named by an id, and a decision is a question about the graph under that model. The boundary cost is a server and a datastore, and revocation latency has four components, because this adapter keeps a copy: the record is the application's own tables, and the relay is what keeps the copy in step with them.

A Zanzibar-style system stores tuples, `(user, relation, object)` such as `user:alice member program:9`, and a model that says how relations compose: assigned directly, computed from another relation on the same object, or followed through a related object, as in "members of the document's program". A condition is a small CEL expression on a tuple, evaluated against the context sent with each question.

| Turnstile | OpenFGA |
|---|---|
| subject, object, operation | user, object, relation; an operation is a relation such as `can_read` |
| environment | the `context` sent with a check, read by conditions |
| subject attribute | a tuple to a reified value: `user:alice member country:US` |
| object attribute | a tuple on the object, or a condition parameter on one |
| a grant written or revoked | a tuple written or deleted |
| policy version | a model published into the store, named by the id the server answers with |
| `decide` | `Check`, with the model id pinned and `consistency` set per operation |
| `scope` | `ListObjects`, then `dynamic([d], d.id in ^ids)` |
| the adapter's working state | the store, a copy of what the tables say, kept in step by the relay |

## What is here

- `Turnstile.Fga`: the `Turnstile.Adapter` implementation. `decide` is one `Check` under the bound model, with `HIGHER_CONSISTENCY` for a write operation and `MINIMIZE_LATENCY` for a read, a constant of the adapter. `scope` is one `ListObjects` turned into a rule over identifiers; the scope cap is 1,000, and at the cap or above it the answer would be short of the truth without saying so, so `scope` emits `[:turnstile, :fga, :scope_fallback]` and fails, and the caller asks per row. `settle/0` drains the outbox, so a test reads a store the tables have reached.
- `Turnstile.Fga.Binding`: the mediated repo, the model file, the tuple mapping, the store, and who wrote and approved the model. `bind/1` validates them once at boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `Turnstile.Fga.Client`: the only path to the server. Six calls, `create_store/2`, `write_model/3`, `check/3`, `list_objects/3`, `read/3`, and `write/3`, each answering a value or a `%Turnstile.Error{reason: :engine_unreachable}`, none of them raising. The endpoint comes first, the store second, and a request struct per call third, because a model id and a consistency are values on a request rather than state on the client: a decision is taken under a version. Every call emits one telemetry event, which is how a shape test counts the engine's own calls.
- `Turnstile.Fga.Client.Fake`: the same behaviour on an `Agent`, in test support. It holds stores, models, and tuples, and it copies what a caller can get wrong: a write is atomic per call, and a duplicate write, a delete of a tuple the store does not hold, a tuple key on both sides of one call, and more changes than one call may carry each change nothing at all. It does not evaluate the model, so what it answers questions from is the tuples it holds directly.
- `Turnstile.Fga.TupleKey` and `Turnstile.Fga.Condition`: a tuple as the store keeps it. A tuple is identified by its user, its relation, and its object; a condition, a name in the model and the parameters it carries, is a value on the tuple rather than part of that identity. That is what makes a changed parameter a delete and a write of one key rather than a second tuple.
- `Turnstile.Fga.TupleMapping`: what an application states about its tables. `object_types/0` is what a reconcile reads by, `objects/2` is every object of a type the tables hold, `changed/2` is which objects one change can have affected, and `tuples/2` is which tuples an object requires. Every answer is read from the rows as they stand rather than computed from the change that arrived, because a tuple can rest on several rows at once and a change names the row it was made on.
- `Turnstile.Fga.Outbox`: the markers the relay works from. A handler on the change event inserts one marker per affected object in the transaction that changed the rows, and a relay runner delivers them: per object, the difference between what the rows require and what `read/3` reports, in calls of at most `Turnstile.Fga.Client.max_tuples_per_write/0` changes. `Turnstile.Fga.reconcile/0` compares the tables with the store, paged by object type, and reports what each holds and the other does not. `Turnstile.Fga.rebuild/1` creates a store, publishes the model, writes every object the tables hold into it, and answers the new store, so a rebuild runs beside the store that is serving.
- `Turnstile.Fga.Relay`: batched, ordered delivery from a Postgres table. One runner per job, a cursor that says how far that runner has got, a wake-up for the process that wrote a row, and an advisory lock so a second node steps aside rather than shipping the same rows twice. `Turnstile.Fga.Relay.Job` is the behaviour a job implements, `read/4`, `deliver/3`, and `options_schema/0`; `Turnstile.Fga.Relay.Entry` is one row on its way out; `Turnstile.Fga.Relay.Pass` is what one pass did; `Turnstile.Fga.Relay.Cursor` is one row per runner. The relay names no subject, no object, and no rule; the repo it is given is one whose calls carry no decision.
- `Turnstile.Fga.Version`: the policy version is the model id the server answers on publish, and the content is the model text under the configured cap. Publishing emits `[:turnstile, :fga, :policy_version]` and stores nothing.
- `Turnstile.Fga.Migration`: the helpers a thin application's migration calls to create the outbox table and the cursor table, both in the application's own database, because a marker is written in the transaction that changed the rows and a pass advances the cursor in the transaction that delivered them.
- Test support, compiled and never published: the tuple mapping for the neutral fixture beside `priv/conformance/model.fga`, the versions module that publishes a tightened model, and the two templates an application's binding is held to: `Turnstile.Fga.TupleMappingCase` for the mapping it declares and `Turnstile.Fga.OutboxCase` for the drain it runs.

The package's `lib` depends on `turnstile`, `ecto`, `ecto_sql`, `nimble_options`, `postgrex`, and `telemetry`. The relay's cursor and its advisory lock are Postgres, which is why the driver is a dependency of `lib`; Boundary checks that no call from `lib` reaches `postgrex` or `ecto_sql` outside the migration helpers.

## Mechanism per rule shape

| Rule shape | Mechanism |
|---|---|
| A role held on a row | a tuple from the user to the relation on the object |
| A test on the subject | membership of the value as an object of its own, because a graph compares by walking rather than by equality |
| A test on the row | a wildcard `user:*` on a relation named for the fact, so what a row states is one tuple rather than one per account |
| A test on the moment | a condition on the tuple carrying the date, against `current_time` in the context of every question |
| A grant held by one kind of subject | a condition on the tuple carrying the kind, against `subject_kind` in the context of every question, since the user string names the account whatever kind asks |
| A rule over a whole type | `ListObjects` under the cap; at the cap the caller asks per row |
| A write gate | the seam refuses a write with no decision for the operation before the model is asked |
| A fact about the session | not modeled: a condition would make every use of the relation demand session context, so the application reads it from the environment before the server is asked |

## One pass of the relay

A pass is one transaction:

1. Ask for the transaction-scoped advisory lock on the runner's name. A runner told no reports the cursor, delivers nothing, and tries again after its idle interval.
2. Read the cursor, then read a batch above it through the job.
3. Deliver the batch through the job.
4. Advance the cursor to the position of the last entry delivered.
5. Commit.

Delivery that fails rolls the pass back, so the cursor stays where it was and the same batch is read again. That is at-least-once delivery in position order, and a job's `deliver/3` is written for a batch it may have seen before; delivering a marker twice costs a read and no write, which is what lets at-least-once stand as correctness. The runner decides only when the next pass runs: at once where the batch filled, after the idle interval where it did not, and after a wait that doubles per failure and is capped where the pass failed. A wake-up is a cast, so the process that wrote the rows is not held up by a delivery; one arriving while a pass is already pending is dropped, because that pass reads everything committed before it runs.

One `write/3` refuses a tuple key that appears in both its deletes and its writes, so a tuple whose condition changed takes two calls: the deletion, then the writing of the same key with the new value on it. Between those two calls the store holds neither the old state nor the new one, and a pass that stops there has committed nothing, so its markers are read again.

Every pass publishes `[:turnstile, :relay, :pass]`, whether it delivered, stepped aside, or failed: measurements `delivered` and, where there was one, `position`; metadata the runner's `name`, its `job`, and either the `%Turnstile.Fga.Relay.Pass{}` or the error term the job reported.

## Latency

Four components for a fact: commit, a relay pass, the engine write, and the check-cache TTL where a cache is enabled. One for a rule: a model publication, which reaches every question at once, because a question moves to another model by being asked under another id. The conformance suite prints the measurement beside its run, the relay pass included, and asserts nothing about it.

## Binding at boot

After the configuration boots with `adapter: {Turnstile.Fga, endpoint: "http://127.0.0.1:8080", store: "01J..."}`, the application binds, publishes, and starts the runner:

```elixir
{:ok, _binding} =
  Turnstile.Fga.Binding.bind(
    repo: MyApp.Repo,
    model: "priv/fga/model.fga",
    mapping: MyApp.TupleMapping,
    author: "the model owner",
    approval: "the change record"
  )

{:ok, _event} = Turnstile.Fga.publish()

children = [{Turnstile.Fga.Relay, runners: [[name: :markers, repo: MyApp.Repo, job: Turnstile.Fga.Outbox]]}]
```

The application calls `Turnstile.Fga.Relay.wake/1` after the write that produced markers. A test calls `drain_once/1` and starts no runner.
