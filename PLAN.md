# Turnstile: the plan

The decision record for the library as it stands: why it is shaped this way, what the shape is, and what would reverse a decision in it. The order the work ran in is history; what a reader needs before adding to the repository is here.

## Why

Turnstile began as three projects wearing one name. One was a library that stops a query from escaping its check. One was a repository that shows four ways to decide the same question. One was a generator that writes the document an assessor reads. Each had a different customer, and each pulled the design its own way. The generator wanted declarations about every adapter. The teaching repository wanted every adapter to keep the idioms of its own engine. The library wanted the smallest thing an application can install. The design tried to serve all three, and the result was eleven packages and about six thousand seven hundred lines in the package that should have been the smallest of them.

The generator is now gone, and with it the capability tables, the control origination split, and the machine-readable output. A table that a person writes takes its place: a control, the thing that holds it, and the test that proves the thing works. That removal is larger than it looks, because most of the declarations in the design existed to be printed rather than to be run.

Two more removals followed from the same question. The ledger kept every authorization fact forever so that a decision could be replayed. No control asked for replay, and the price was a table, a counter row, a genesis migration, and a lock on every write that touched a fact. It is now a list of changed objects that OpenFGA drains and then deletes. Audit storage went the same way. The library emits a change event where the change happens, and whoever owns the log pipeline stores it. A library that emits can be tested. A library that stores has taken on a job that belongs to the system around it.

What remains is two projects instead of three, and they want compatible things. An adopter wants a small dependency whose surface fits on one screen. A reader wants to see where four authorization models truly differ. One discipline serves both: keep each decision in a module that holds nothing and calls nothing, and keep each module that touches a database or an engine thin enough to read in one sitting. For the adopter, that discipline is the reason the library can promise anything at all. For the reader, it is what makes the four adapters comparable, because the parts that differ are no longer buried inside the parts that do not.

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

## §1 Packages

A package exists for one of two reasons: it carries a dependency that the library must not force, or it is a choice that an adopter makes.

| Package | Published | Why it exists |
|---|---|---|
| `turnstile` | Yes | The contract. Runtime dependencies: `ecto`, `telemetry`, `nimble_options`, which validates the configuration and the `turnstile:` option, and `stream_data`, which the conformance templates in `lib` draw from. |
| `turnstile_credo` | Yes | Two checks for adopters. It carries `credo`. |
| `turnstile_rbac` | Yes | An adapter: roles in Elixir. |
| `turnstile_postgres` | Yes | An adapter: row-level security. |
| `turnstile_cerbos` | Yes | An adapter: a policy engine beside the application. |
| `turnstile_fga` | Yes | An adapter: a relationship engine, and the outbox that keeps it in step. |
| `turnstile_relay` | Yes | Batched, ordered delivery from a Postgres table: one runner, a cursor, and a wake-up. It depends on nothing else here, and `turnstile_fga` is its only consumer in this repository. |
| `turnstile_dev` | No | The engines this repository tests against: the Cerbos launcher, the OpenFGA launcher, and the structure test. |
| `example` | No | The CUI domain and its web layer. |
| `example_rbac`, `example_postgres`, `example_cerbos`, `example_fga` | No | One build of the example for each adapter. |

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

Turnstile.authorize(subject, operation, object, opts)      # {:ok, decision} | {:error, error}
Turnstile.check(subject, operation, object, opts)          # boolean
Turnstile.batch(subject, operation, objects, opts)         # a verdict per object
Turnstile.filter(subject, operation, objects, opts)        # the objects allowed, from a list
Turnstile.scope(subject, operation, object_type, opts)     # {rule, decision}
Turnstile.explain(subject, operation, object, opts)        # the answer with what produced it on meta
Turnstile.review(subject, subjects, operation, over, opts) # a rule or the allowed objects, per subject
```

- A subject is a `{kind, id}` tuple and an object a `{type, id}` tuple. The options are `env`, a map of the facts only the caller knows, and `operation_id`, the identifier every record of one operation shares. `authorize` has a raising form, which is what a context function that has nothing to say about a denial calls.
- `%Turnstile.Answer{verdict, reason, version, meta}` is what an adapter answers, and `meta` belongs to the adapter. `%Turnstile.Decision{}` is what the port stamps from an answer, and it is what the seam reads from the `turnstile:` option.
- `%Turnstile.Error{reason, detail}` is the one exception.
- Configuration has three keys: `adapter`, `clock`, and `caps`. The clock is a zero-arity function, and its default reads the system clock. `caps` has one key, the policy text a version carries by value before a pointer takes its place.

An adapter implements nine callbacks, five of them optional: `authorize`, `check`, `batch`, and `scope`, each taking the subject, the operation, the object or object type, the environment, and the adapter's options; `scope_cap`, the largest population it will narrow over; and the optional `explain`, `around_query`, `options_schema`, and `settle`. `docs/reference.md` §4 carries them with their results.

Every callback is an operation. None of them declares anything about an operation. An adapter that cannot narrow a query answers at the call, and that answer is truer than a declaration would be, because Cerbos can narrow a query for one resource and not for another.

The port derives what it can from what an adapter answers, and an adapter that raises produces a denial, with the exception travelling in the decision event.

## §4 The events

Two events, and the library publishes both and stores neither. Each payload carries what a consumer needs to build an OCSF record without inventing a value. The library carries the meaning. The consumer chooses the format and the schema version.

`[:turnstile, :change]` is published inside the write transaction, where the change is computed. `[:turnstile, :decision]` is published after each decision, which is a read and so has no transaction. `docs/reference.md` §7 carries both payloads field by field, and `Example.Siem` is the worked consumer: it maps both events to OCSF and holds the result in memory, which keeps the mapping under test without putting a schema version in any published package.

What the library guarantees:

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

Two numbers run in CI. The runtime dependency count of `turnstile` must stay at four, and it is a test in that package's own suite, over the dependencies of its Mix project. The line coverage of every `core/` module must stay at one hundred percent, and it is `mix test.core` and a CI job of its own, because a partitioned run measures a part of the suite; the run sets an environment variable each package's `test_coverage` reads, and it reads the applications it covers off the tree.

## §6 What proves what

| Kind | What it proves | Where |
|---|---|---|
| Conformance suites | A module that touches the world behaves the same as every other of its kind, and which requests it cannot narrow | `AdapterCase` and `RepoCase` in `turnstile`; `JobCase` in `turnstile_relay`; `OutboxCase`, `GuardCase`, and `TupleMappingCase` in `turnstile_fga` |
| Properties | A decision is right for inputs nobody thought of | The classifier, the drain, the engine codecs, the banner, and relay durability |
| Scenarios | The example obeys its own rules, under every adapter | The nine groups, in the four thin applications |
| Shape tests | The work is the size it should be | Query counts, event counts |

The properties and the suites divide by the rule of §2. A property tests a module in `core/`. A suite tests a module in `adapter/` against the real database or engine.

## §7 The NIST line

One table, in `docs/reference.md` §10, written and maintained by a person. No code reads it. It pairs each control with the thing that holds it and the test that proves the thing works, and it says of AU-5 and AU-9 that they sit outside the library, which is the same split the events rest on. A control is cited beside a scenario in the table of `docs/reference.md` §1, and the scenario macro tags each test with the controls that table cites, so a control number is written in one place.

## §8 What would reverse a decision here

- **A team asks for replay.** Add a consumer that stores change events. History starts that day, and nothing in the design blocks it.
- **The repository grows past about eighty modules.** The structure checks earn their cost again. The rules are already written as this plan's §2.
- **An application wants durable audit delivery at low volume.** Point it at Oban, which already inserts a job in the write transaction. `turnstile_relay` earns its place only where records are batched, ordered, and driven by a cursor.
- **The interception cannot be proved across every Ecto path.** Then the promise fails, and the honest answer is that enforcement belongs in a data layer. That would be a different project.