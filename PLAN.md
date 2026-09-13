# Turnstile: the plan

## Why

Turnstile began as three projects wearing one name. One was a library that stops a query from escaping its check. One was a repository that shows four ways to decide the same question. One was a generator that writes the document an assessor reads. Each had a different customer, and each pulled the design its own way. The generator wanted declarations about every decider. The teaching repository wanted every decider to keep the idioms of its own engine. The library wanted the smallest thing an application can install. The design tried to serve all three, and the result was eleven packages and about six thousand seven hundred lines in the package that should have been the smallest of them.

The generator is now gone, and with it the capability tables, the control origination split, and the machine-readable output. A table that a person writes takes its place: a control, the thing that holds it, and the test that proves the thing works. That removal is larger than it looks, because most of the declarations in the design existed to be printed rather than to be run.

Two more removals followed from the same question. The ledger kept every authorization fact forever so that a decision could be replayed. No control asked for replay, and the price was a table, a counter row, a genesis migration, and a lock on every write that touched a fact. It is now a list of changed objects that OpenFGA drains and then deletes. Audit storage went the same way. The library emits a change event where the change happens, and whoever owns the log pipeline stores it. A library that emits can be tested. A library that stores has taken on a job that belongs to the system around it.

What remains is two projects instead of three, and they want compatible things. An adopter wants a small dependency whose surface fits on one screen. A reader wants to see where four authorization models truly differ. One discipline serves both: keep each decision in a module that holds nothing and calls nothing, and keep each module that touches a database or an engine thin enough to read in one sitting. For the adopter, that discipline is the reason the library can promise anything at all. For the reader, it is what makes the four deciders comparable, because the parts that differ are no longer buried inside the parts that do not.

The layout this repository was heading for was written for the eleven-package version: six directory groups, twenty-two numbered rules, five custom checks, and fifteen metrics. It was right to be that large, because a hundred and seventy modules cannot be held in order by good intentions. At forty modules that apparatus costs more than it returns, and the author has under five hours a week. So this plan keeps the rule the apparatus existed to protect, and it drops most of the machinery that enforced the rule.

The rule is one sentence. **A decision lives in a module that a test can call directly.**

Everything else follows. A module either decides or it touches the world. There is no third kind, and a module that does both is divided until there is not. What touches the world is proved by running it against the real thing, and that is what the conformance suites are for. What decides is proved directly, and that is what the properties are for. The promise that the library exists to make, that a query cannot escape its check, is itself a decision, so it lives in a module that a test calls directly. That is not a coincidence. It is the reason the rule is worth keeping after everything else was cut.

Three tools enforce it, and each does only what it can see. The `boundary` library compiles the rule that no package reaches into the interior of another. One small test asserts the two things a parser can see for itself: one module to a file, and no call to the outside world from a module that decides. A person enforces the rest while reading a diff. Five custom checks and a report would be about forty hours of work before an adopter gained anything from them. The same rules hold for a hundred lines of test and the habit of reading carefully.

Four things go that a reasonable person would want. There is no history, so nothing can be replayed, and any history added later begins on the day it is added. There is no generated evidence, so an adopter writes the statement. There is no machine-checked placement, so a module can land in the wrong directory and only a reader will notice. There is no stored audit, so an application that attaches no consumer writes nothing down. Each is a deliberate trade. Each is reversible by adding something rather than by rewriting something, and that property is what made each acceptable.

## The commitments

1. **The library emits records. It does not write statements, keep history, or store logs.**
2. **A decision lives in a module that a test can call directly, and a module that touches the world does nothing else.**
3. **The surface is what a test can assert. The interior is arranged so a test can reach every decision.**
4. **Each tool enforces only what it can see, and a person enforces the rest.**
5. **The conformance suites are the asset. A cut that loses a suite needs a better reason than a cut that loses code.**

---

# Part 1: The shape

## §1 Packages

A package exists for one of two reasons: it carries a dependency that the library must not force, or it is a choice that an adopter makes.

| Package | Published | Why it exists |
|---|---|---|
| `turnstile` | Yes | The contract. Runtime dependencies: `ecto`, `telemetry`, `nimble_options`, which validates the configuration and the `turnstile:` option, and `stream_data`, which the conformance templates in `lib` draw from. |
| `turnstile_credo` | Yes | Two checks for adopters. It carries `credo`. |
| `turnstile_rbac` | Yes | A decider: roles in Elixir. |
| `turnstile_postgres` | Yes | A decider: row-level security. |
| `turnstile_cerbos` | Yes | A decider: a policy engine beside the application. |
| `turnstile_fga` | Yes | A decider: a relationship engine, and the outbox that keeps it in step. |
| `turnstile_relay` | Yes | Batched, ordered delivery from a Postgres table: one runner, a cursor, and a wake-up. It depends on nothing else here, and `turnstile_fga` is its only consumer in this repository. |
| `turnstile_dev` | No | The engines this repository tests against: the Cerbos launcher, the OpenFGA launcher, and the structure test. |
| `example` | No | The CUI domain and its web layer. |
| `example_rbac`, `example_postgres`, `example_cerbos`, `example_fga` | No | One build of the example for each decider. |

The unpublished packages are why the published ones stay small. Starting an engine's server takes `muontrap`, and that dependency belongs to this repository rather than to an application that installs the library.

Two pieces of test support stay published, because a published module calls them: the ephemeral Postgres cluster, which the task that dumps a thin application's schema raises, and the sandbox setup, which an adapter outside this repository uses as the adapters here do. What a suite is run over is not published. A population sits in the test tree of the package that owns it, and the conformance template reads one through a behaviour its caller supplies, so no published package names a schema or a rule.

## §2 Inside a package

Three places, not six.

| Place | Holds | Documented | Who may name it |
|---|---|---|---|
| The root | The public modules: the functions an adopter calls, the types they receive, and the behaviours they implement | `@moduledoc` | Anyone |
| `core/` | Modules that decide. They hold nothing and call nothing outside their own package. | `@moduledoc false` | The root, `core/`, and `adapter/` |
| `adapter/` | Modules that touch a database, an engine, a file, the clock, or a process | `@moduledoc false` | The root and `adapter/` |

Rules:

- The path names a module the file defines, and every other module the file defines is named under that one. Two gates of the repository forbid the flatter reading, one module to a file and nothing else. `mix xref --label compile-connected --fail-above 0` holds a `use`d module to being a leaf, so the structs a declaration macro builds stay in the file that builds them. `mix xref --format cycles --fail-above 0` refuses a cycle between files, so schemas whose associations refer to one another share one. `StructureTest` names each file of the second kind with its reason.
- A function that decides and also touches the world is divided until no function does both.
- A module in `core/` calls no other package's interior, and no adapter. Inside a package the calls run one way: the root reaches `adapter/` and `core/`, and `adapter/` reaches `core/` to have something decided. A decision that needs the world is divided until the half that decides needs none of it.
- An adapter may call another adapter in its own package. At this size, a boundary for each adapter costs more than the isolation returns.
- Errors, structs, and behaviours live at the root, because they are public. There are few enough to read as one list.

## §3 The surface

This is the whole of what an adopter touches.

```elixir
use Turnstile.Repo                 # the interception
use Turnstile.Schema               # which fields are facts, and what kind of thing this is

Turnstile.authorize(subject, operation, object, env)   # {:ok, answer} | {:error, error}
Turnstile.check(subject, operation, object, env)       # boolean
Turnstile.scope(query, subject, operation, env)        # a narrowed query
Turnstile.review(subjects, operation, query, env)      # rows, derived from scope
Turnstile.exempt(fun)                                  # run without a check, on purpose
```

- A subject and an object are `{type, id}` tuples. The environment is a map.
- `%Turnstile.Answer{verdict, reason, version, meta}` is the one result struct. `meta` belongs to the decider.
- `%Turnstile.Error{reason, detail}` is the one exception.
- Configuration has three keys: `decider`, `repo`, and `clock`. The clock is a zero-arity function, and its default reads the system clock.

A decider implements three callbacks, one of them optional:

```elixir
[callback](callback) authorize(request) :: {:ok, Answer.t()} | {:error, term}
[callback](callback) scope(request, query) :: {:ok, query} | {:error, :unsupported} | {:error, term}
[callback](callback) batch(requests) :: {:ok, [Answer.t()]} | {:error, term}   # optional
```

Every callback is an operation. None of them declares anything about an operation. A decider that cannot narrow a query answers `{:error, :unsupported}` at the call, and that answer is truer than a declaration would be, because Cerbos can narrow a query for one resource and not for another.

Core derives `check`, `review`, and a default `batch` from these. A decider that raises produces a denial, and the exception travels in the decision event.

## §4 The events

Two events. Each payload carries what a consumer needs to build an OCSF record without inventing a value. The library carries the meaning. The consumer chooses the format and the schema version.

### `[:turnstile, :change]`

Emitted inside the write transaction, where the change is computed.

| Field | Value | What a mapper does with it |
|---|---|---|
| `operation` | `:create`, `:update`, or `:delete` | The OCSF activity |
| `kind` | `:user`, `:group`, `:role`, or `:entity`, declared on the schema | The OCSF class |
| `target` | `{type, id}` of the row that changed | The entity type and identifier |
| `changes` | a map of field to `{old, new}`, for the fact fields that changed | The attributes before and after |
| `actor` | `{kind, id}` of the subject whose authorization allowed the write, or the library where an exemption carried it | The actor |
| `actor_kind` | `:user`, `:non_person_entity`, or `:privileged` | Whether the actor is a person or a process |
| `time` | the configured clock at the moment of the write | The event time |
| `operation_id` | one identifier shared by every event of one operation | The correlation identifier |
| `schema` | the Ecto schema module | Context a mapper may need |

### `[:turnstile, :decision]`

Emitted after each decision. A decision is a read, so it has no transaction.

| Field | Value |
|---|---|
| `subject`, `subject_kind` | `{kind, id}`, and `:user`, `:non_person_entity`, or `:privileged` |
| `operation` | the operation that was asked about |
| `object` | `{type, id}`, or the query for a narrowing call |
| `verdict` | `:allow`, `:deny`, or `:scoped` |
| `reason` | an atom |
| `decider`, `version` | the module, and its policy version string |
| `duration` | microseconds |
| `env` | the environment map as the caller gave it |
| `exception` | the exception, when a decider raised and the decision failed closed |
| `time`, `operation_id` | as above |

### What the consumer adds

The class, category, severity, and type identifiers, its own product metadata, and the shape of the OCSF actor. Each of those depends on the schema version the consumer targets, and the identifiers move between versions, so they stay outside the library. `Example.Siem` maps both events to OCSF and holds the result in memory, which keeps the mapping under test without putting a schema version in any published package.

### What the library guarantees

| Id | Guarantee |
|---|---|
| E1 | A single-row write to an audited schema emits one change event, carrying every fact field that changed. |
| E2 | A bulk write to an audited schema raises and emits nothing. |
| E3 | A write that goes around the interception emits nothing. |
| E4 | A consumer that writes to the same repository from its handler joins the write transaction. |

What it does not guarantee: that a record is stored, that a handler keeps running, that the change committed, or that the old value was current at the moment of the write. The old value is the value the caller loaded.

## §5 What enforces what

| Rule | Enforced by |
|---|---|
| No package reaches into the interior of another | `boundary`, at compile time |
| The path names a module the file defines, and its other modules are named under that one | `StructureTest` in `turnstile_dev` |
| A module in `core/` makes no call to the outside world | `StructureTest` |
| A module in `core/` names no module in `adapter/` | `StructureTest` |
| Core and adapter modules carry `@moduledoc false` | `StructureTest` |
| An adopter's queries reach the check | `Turnstile.Credo.UnmediatedRepo` and `NoRawSQL` |
| Placement, naming, division of a mixed function | Review |

`StructureTest` reads the syntax tree and is a few hundred lines. The `boundary` library cannot see a call to Elixir's own modules or to Erlang, which is why the effect rule belongs to the test and not to a dependency list.

Two numbers run in CI: the runtime dependency count of `turnstile`, which must stay at four, and the line coverage of every `core/` module, which must stay at one hundred percent. Neither is wired yet. They go in at step 12, where the last package is placed and every `core/` exists; a partitioned test run measures coverage over a part of the suite, so the second number needs a run of its own.

## §6 What proves what

| Kind | What it proves | Where |
|---|---|---|
| Conformance suites | A module that touches the world behaves the same as every other of its kind, and which requests it cannot narrow | `DeciderCase` and `RepoCase` in `turnstile`; `JobCase` in `turnstile_relay`; `OutboxCase`, `GuardCase`, and `TupleMappingCase` in `turnstile_fga` |
| Properties | A decision is right for inputs nobody thought of | The classifier, the drain, the engine codecs, the banner, and relay durability |
| Scenarios | The example obeys its own rules, under every decider | The nine groups, in the four thin applications |
| Shape tests | The work is the size it should be | Query counts, event counts |

The properties and the suites divide by the rule of §2. A property tests a module in `core/`. A suite tests a module in `adapter/` against the real database or engine.

## §7 The NIST line

One table in `docs/reference.md`, written and maintained by a person. No code reads it.

| Control | What holds it | Test |
|---|---|---|
| AC-3 Access enforcement | The interception and deny by default | `RepoCase`, `DeciderCase`, the `enf` scenarios |
| AC-5 Separation of duties | Rule C9 | The `sod` scenarios |
| AC-6 Least privilege | Rules C1 and C2 | The `lp` scenarios |
| AC-6(7) Review of privileges | `Turnstile.review/4`, run on a schedule, with the reports kept | `rvw-01`, `lp-08` |
| AC-2, AC-2(4) | The change event. The system stores it. | The `aud` scenarios |
| AU-2, AU-3, AU-12 | Change events and decision events | The `aud` scenarios |
| AU-5 Audit failure alert | The telemetry handler failure event | Outside the library |
| AU-9 Protection of audit records | The store of the consumer | Outside the library |
| IA-11 Re-authentication | Rule C8, from an environment fact | The `reauth` scenarios |
| Revocation | The outbox of `turnstile_fga` | `rev-01`, `rev-07` |

Check the control numbers against the catalog before this table is published.

---

# Part 2: What is deleted

## §8 By reason

**Because a generated document is gone:** `turnstile_assess`, its Mix task, `docs/assess.md`, the assessment context and its glossary, control origination, baselines, parameters, the OSCAL output, the control id on each scenario and its lint, `Turnstile.Capabilities` with the four application modules that implement it, and the policy version workflow with its author and approval.

**Because history is gone:** `turnstile_ledger` as a package, the ledger behaviour, the fold, the memory ledger, fact events, the bulk fact API, replay in three deciders, and the past-date review.

**Because storage belongs to the system:** the audit sink behaviour, the changes table and its migration, and the example's sink. The relay processes are not deleted. They become `turnstile_relay`, which holds no authorization concept and which an application can use to ship audit records without losing one.

**Because the surface must fit on one screen:** `Subject`, `Object`, `Decision`, `Reason`, `Explanation`, `Edge`, `Id`, `PolicyVersion`, `Scope`, `Environment`, `Exemption`, the five exception modules, the clock behaviour with its system implementation, the `relationship` macro, the review modules with their Mix task, and the repository override path.

**Because bulk writes on audited schemas now raise:** the lock read, the bulk write path, and the old-row machinery.

**Because the library is now small enough to read:** the six-group layout, the twenty-two numbered rules, the five custom structure checks, the fifteen metrics, and the report script.

## §9 What the deletions cost

| Lost | Cost | How it returns |
|---|---|---|
| Replay and past-date review | An investigator cannot reconstruct a decision from last March | A consumer that stores change events durably, from the day it is attached |
| The generated statement | An adopter writes it | A separate tool that reads the scenario results |
| Explanations | The matched rule and the OpenFGA path leave the answer | A field on `meta`, per decider |
| Three conformance cases | Capabilities, sink, and review have no template | None were built, and no scenario is lost with them |
| Machine-checked placement | A misplaced module survives until a reader finds it | The checks, if the repository grows again |

---

# Part 3: The work

## §10 Defects to fix along the way

| Defect | Fix | Step |
|---|---|---|
| The banner unions the country lists of its portions, so a reader can pass the banner and fail a portion | Correct rule C4 first, then the code | 1 |
| Code reads the wall clock outside the configured clock | Take the clock from configuration and pass the time as a value | 4, 9 |
| Two deciders rescue database driver errors for a driver they do not carry | Remove the rescue. Core fails closed on any exception from a decider. | 7 |
| `Turnstile.Cerbos` depends on the test kit for its propagation wait | Wait with a monotonic clock in an adapter | 8 |
| One file holds four modules from two contexts | Divide the file | 3 |
| `turnstile_fga` calls `:httpc` and does not start `:inets` | One line in its `mix.exs` | 9 |

## §11 Steps

Each step is one merge, and `mix quality` passes at the end of each.

1. **Correct the banner.** Done. Rule C4 in the reference now says a banner releases to no country a portion withholds, the scenario that catches the fault is in the committed list, `Example.Controls` intersects rather than unions, and each binding says where the banner it reads is kept.
2. **Split `turnstile_dev`.** Done. The package holds the two launchers and nothing else, and the four suites that raise a server take it as a test-only dependency, so no published package carries `muontrap`. The cluster and the sandbox setup stayed published for the reason §1 gives. The population moved into the test tree behind `Turnstile.Conformance.World`. Nothing changed semantically, and the published dependency list shrank. Step 3 adds `StructureTest` to this package.
3. **One module to a file.** Done. `Turnstile.Facts.Context`, the six adapter conformance modules, and the two controllers moved to the paths their names give; the conformance modules left `priv/conformance` for their packages' `test/support`, and what an engine reads as text stayed behind. `StructureTest` in `turnstile_dev` carries the rule §2 states and nothing else, over every package's `lib` and `test/support`. One file is named as its exception, for the reason §2 gives.
4. **Collapse the surface.** Done for the values §3 states. A subject and an object are `{kind, id}` and `{type, id}` tuples, `%Turnstile.Answer{verdict, reason, version, meta}` is the one result with `meta` the decider's own, `%Turnstile.Error{reason, detail}` is the one exception with nine reasons, the environment is a map the port stamps `now` into, and the clock is the zero-arity function the configuration names, which the applications read a recorded moment from as well. `Subject`, `Object`, `Reason`, `Explanation`, `Scope`, `Environment`, and the five exception modules are deleted. The type deletions of §8 that remain are the ones the ledger and the seam record with, and each goes with the thing that records it, in step 5.
5. **Emit the change event.** One event for each write, inside the transaction, from the changeset, with the payload of §4. Add the kind declaration to `use Turnstile.Schema`. Refuse bulk writes on audited schemas. Delete the audit store, and make `Example.Siem` a handler that maps to OCSF. Assert E1 to E4 in `RepoCase`. The fact-writing API over that store goes with it, and so do the types step 4 left: `Decision`, `Edge`, `Id`, `PolicyVersion`, and `Exemption` each go with the ledger row, the record, or the seam path that carried them. What stays is what still has a reader: the ledger behaviour, its fold, `FactEvent`, and the `turnstile_ledger` package, which the FGA projection drains and each adapter records its policy version in. Those go in step 10, where the projection takes its markers from the relay instead and the version publishing keeps its telemetry branch alone.
6. **Rename the packages and place the contract.** `turnstile_core` becomes `turnstile`, and `turnstile_example` becomes `example`. Move its modules into `core/` and `adapter/`, write the boundary declarations, extend `StructureTest` with the effect rule, and write the classifier property.
7. **`turnstile_rbac`.** Place its modules, write its declarations, and remove its rescue clause. It is the smallest decider, so it proves the pattern.
8. **`turnstile_postgres` and `turnstile_cerbos`.** Place, declare, remove the rescue and the test-kit dependency, and write the Cerbos codec property.
9. **`turnstile_relay`.** Build the supervisor, the lock, the worker, the wake-up, and the job behaviour, with `JobCase` and the durability property. It has no consumer yet, so it is proved by its own tests.
10. **`turnstile_fga`.** Build the marker outbox on the relay, take in the projection modules, and write the drain property and the codec property.
11. **`example` and `ExampleWeb`.** Place the modules, divide the contexts from their queries, and move the banner property onto the pure module.
12. **The thin applications.** Place, change configuration and migrations, replace the capability declarations with test tags, and wire the two numbers of §5.
13. **Close.** Change the documents of §12, record this plan as a decision record, and delete Parts 2 and 3.

Steps 1 to 5 change behaviour and the surface, and so do steps 9 and 10, which build the relay and move the projection onto it. Steps 6 to 8, 11, and 12 move code without changing behaviour. Keeping that line makes each review tractable.

## §12 Documents

| Document | Change |
|---|---|
| `docs/reference.md` | The surface of §3, the event payloads of §4 with their OCSF reading, the control table of §7, the corrected rule C4, and the scenario changes |
| `docs/testing.md` | The four kinds of test in §6, the case list, and the `turnstile_dev` application |
| `docs/code.md` | The three places of §2, the events, and the four guarantees |
| `docs/assess.md` | Delete. Its table moves to the reference. |
| `docs/delivery.md` | Remove the assessment stage. Keep the split where the library emits and the system stores. |
| Glossaries | Remove the assessment, capability, explanation, and ledger words. Add *change event*, *audited schema*, and *consumer*. |
| `CLAUDE.md` | One paragraph: before adding a module, decide whether it decides or touches the world, and put it in the matching place. |

## §13 What would reverse a decision here

- **A team asks for replay.** Add a consumer that stores change events. History starts that day, and nothing in the design blocks it.
- **The repository grows past about eighty modules.** The structure checks earn their cost again. The rules are already written as this plan's §2.
- **An application wants durable audit delivery at low volume.** Point it at Oban, which already inserts a job in the write transaction. `turnstile_relay` earns its place only where records are batched, ordered, and driven by a cursor.
- **The interception cannot be proved across every Ecto path.** Then the promise fails, and the honest answer is that enforcement belongs in a data layer. That would be a different project.