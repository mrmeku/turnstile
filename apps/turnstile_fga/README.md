# Turnstile on OpenFGA

The adapter whose working state is a relationship graph in a store of its own: `Turnstile.Fga`. The server is OpenFGA 1.19.0, pinned in the flake (`docs/reference.md` §12), self-hosted with a datastore of its own. Facts become tuples in a store, rules become a model that is immutable and named by an id, and a decision is a question about the graph under that model.

The one structural difference from the adapters whose state is the application's tables: this one keeps a copy. The ledger is the record, and the projector is what keeps the copy current, which is why this adapter requires a ledger.

- `Turnstile.Fga.Client`: the only path to the server. Eight calls, `create_store/2`, `write_model/3`, `check/3`, `batch_check/3`, `list_objects/3`, `expand/3`, `read/3`, and `write/3`, each answering a value or a `Turnstile.Error.Engine`, none of them raising. The endpoint comes first, the store second, and a request struct per call third: `Turnstile.Fga.Client.Check`, `.BatchCheck`, `.ListObjects`, `.Expand`, `.Read`, and `.Write`, with `.Page` and `.Tree` as the answers that are more than a value. A model id and a consistency are values on a request rather than state on the client, because a decision is taken under a version.
- `Turnstile.Fga.Client.Fake`: the same behaviour on an `Agent`, in test support. It holds stores, models, and tuples, and it copies what a caller can get wrong: a write is atomic per call, and a duplicate write, a delete of a tuple the store does not hold, a tuple key on both sides of one call, and more changes than one call may carry each change nothing at all. It does not evaluate the model, so what it answers questions from is the tuples it holds directly, in the types the real client answers in.
- `Turnstile.Fga.TupleKey` and `Turnstile.Fga.Condition`: a tuple as the store keeps it. A tuple is identified by its user, its relation, and its object; a condition, a name in the model and the parameters it carries, is a value on the tuple rather than part of that identity. That is what makes a changed parameter a delete and a write of one key rather than a second tuple.
- `Turnstile.Fga.TupleMapping`: what an application states about its facts. `object_types/0` is what reconcile reads by, `touched/2` is which objects one fact event can have changed, and `tuples/2` is which tuples an object requires. Both of the last two read the fold rather than the event alone, because a tuple can rest on several facts at once and an event names the fact it changed.
- `Turnstile.Fga.Projector`: `Turnstile.Projection` over that mapping. `drain_once/1` reads the events above the checkpoint, folds the ledger, and per touched object writes the difference between what the fold requires and what `read/3` reports, in calls of at most `Turnstile.Fga.Client.max_tuples_per_write/0` changes. `reconcile/1` compares the fold with the store, paged by object type, and reports what each holds and the other does not. `rebuild/1` creates a store, publishes the model, folds into it from position zero, and answers the new store, so a rebuild runs beside the store that is serving.
- `Turnstile.Fga.Checkpoint` and `Turnstile.Fga.Migration`: how far a store has been drained, one row per store in the application's own database, and the helper a thin application's migration calls to create that table. The row is in the database rather than the store because it advances in step with a write the server acknowledged, and a store that no row names stands at zero, which is where genesis sits.
- `priv/conformance/`: the tuple mapping for the neutral fixture, and the model those tuples are read under. The test run compiles the module; an application loads neither.

`glossary.md` defines the words this package owns. The package's `lib` depends on `turnstile_core`, `turnstile_ledger`, `ecto`, `ecto_sql`, and `nimble_options`; `postgrex` serves its own tests only, and Boundary checks that no call from `lib` reaches it.

## The checkpoint and the two calls a rewrite takes

The checkpoint advances after each acknowledged write, to the position of the last event every object of which is done. One `write/3` refuses a tuple key that appears in both its deletes and its writes, so a tuple whose condition changed takes two calls: the deletion, and then the writing of the same key with the new value on it. Between those two calls the store holds neither the old state nor the new one, so the checkpoint stays below that event until the second call is acknowledged.

A drain that fails leaves what it had acknowledged in place and a checkpoint that says exactly which events that state satisfies. The next drain reads from there, computes the difference again, and writes what is left, which is why a drain interrupted part way converges rather than repeating writes the store already holds.

## What the projector needs from an application

Three things: a mapping module, the store id it drains into, and the ledger to read. The drain interval belongs to the process a thin application starts beside its reconcile scheduler. A test drives `drain_once/1` and `reconcile/1` itself, against the fake or against a server, and starts no process of the projector's.

## The pieces the decision path rests on

A decision under this adapter is a question about tuples that the projector put in the store, under a model published as a policy version. The client, the mapping, the projector, and the checkpoint are what that rests on, and each of them is drivable on its own: the client through the fake, the mapping as a function of a fold, the projector one drain at a time.
