# Turnstile: testing
*The environment a run sets up, how a test owns its state so `async: true` is the default, the four kinds of test and what each proves, and what CI runs. Decided: Nix for the toolchain and every service, no Docker; an ephemeral Postgres cluster per `mix test` run; shape tests, counts and not timings, on every pull request.*

## 1. The principle

**Every test owns its state.** Its own database connection, its own clock, its own configuration, its own Cerbos when it changes policies, its own OpenFGA store, its own operation ids, its own processes. Shared mutable globals are what force `async: false`; each one in §5 has a pattern that removes it. `async: false` is a tagged exception with a reason in the tag, never a default.

## 2. Environment: the flake is the pin

`flake.nix` provides the dev shell and the CI environment, from nixpkgs `nixos-unstable` locked in `flake.lock`:

- the toolchain: `beam.packages.erlang_29.elixir_1_20`, which is OTP 29.0.6 and Elixir 1.20.4 on the locked branch, so no overlay is needed;
- `postgresql_18`, written explicitly and never as the bare `postgresql` alias, which is 18 on unstable and 17 on both stable branches;
- `openfga` from nixpkgs, 1.19.0;
- Cerbos 0.55.0, which is in no nixpkgs branch, from its release archive: a `stdenvNoCC` derivation that `fetchurl`s `cerbos_0.55.0_<Linux|Darwin>_<x86_64|arm64>.tar.gz` with a hash per system (Linux x86_64, Linux arm64, Darwin arm64, Darwin x86_64) recorded in the flake;
- all four as binaries on the path, not as services; tests start their own (§3, §4);
- `services-flake` with `process-compose` for day-to-day services: `nix run .#services` brings up its `postgres` service plus Cerbos and OpenFGA as plain process-compose processes wrapping the binaries, since services-flake has no module for either, on local ports for running a thin app by hand;
- `direnv` with `use flake`, so entering the directory is entering the environment.

Each pin, and where it was verified on 2026-09-07 (the full table with URLs is `docs/reference.md` §11):

| Pin | Version | Verified at |
|---|---|---|
| nixpkgs `nixos-unstable` | head `c043004d…`, 2026-09-05 | stable 26.05 has openfga 1.14.2, so unstable is the branch matching every pin at once |
| `beam.packages.erlang_29` | OTP 29.0.6 | `pkgs/development/interpreters/erlang/29.nix` on master and `nixos-unstable` |
| `elixir_1_20` | 1.20.4, minimum OTP 27, maximum OTP 29 | `pkgs/development/interpreters/elixir/1.20.nix` |
| `postgresql_18` | 18.6 | `pkgs/servers/sql/postgresql/18.nix`; the alias default is `all-packages.nix` |
| `openfga` | 1.19.0 | `pkgs/by-name/op/openfga/package.nix`; release published 2026-08-25 on GitHub |
| Cerbos | 0.55.0, published 2026-08-13 | absent from nixpkgs, 404 on every branch; the GitHub release API, asset pattern: tag has `v`, filename does not, OS names capitalized |
| services-flake | active, last commit 2026-08-18 | its repository; no cerbos or openfga service module |

On Darwin the Cerbos binary reaches the machine as a tarball unpacked into the Nix store rather than as a notarized bundle, so no quarantine attribute is attached to it and Gatekeeper does not prompt. That finding is recorded in a comment beside the derivation in `flake.nix`.

CI runs `nix develop --command mix quality`; dev and CI are the same closure. There is no `docker-compose.yml`, no `.tool-versions`, and no other documented path. In the shell the flake gives, `cerbos --version` prints 0.55.0 and `openfga version` prints 1.19.0.

## 3. The ephemeral cluster

`mix test` does not touch the dev services. `test_helper.exs` in every app calls `Turnstile.Test.Cluster.start/1` (shipped in `turnstile` under `Turnstile.Test`, so a third party's adapter can run Tier 1 with it; it raises on failure), which:

1. runs `initdb` into `tmp/pg-<random>/` with `--auth=trust`, and `pg_ctl start` with `-k <that dir>` and `-c listen_addresses=''`: a unix socket, no TCP port, nothing to collide with; plus `fsync=off`, `synchronous_commit=off`, `full_page_writes=off` for speed;
2. creates two roles, `turnstile_owner`, which owns the tables and runs migrations, and `turnstile_app`, which does not own them and carries `NOBYPASSRLS`, the shape row-level security needs (`docs/reference.md` §4); and two databases, `turnstile_test` and `turnstile_committed`;
3. runs the migrations the caller names, as the owner, through the `migrate:` function the caller passes, once per database, with an owner-role repo whose dynamic instance points at that database. A thin app passes `Ecto.Migrator` over its own `priv/repo/migrations`; `turnstile_fga` and `turnstile_relay` pass their migration helpers through a test migration of the kind an application writes; `turnstile_postgres` passes its conformance row-level security migration. `turnstile`'s `lib` depends on `ecto` alone, and the cluster runs `initdb`, `pg_ctl`, and `psql` as commands and calls only `Ecto.Repo` functions, which is why it takes a migration function rather than calling `Ecto.Migrator` itself. The sandbox helper is `ecto_sql`, so it sits in `Turnstile.Test.Sandbox` beside it, and the `:manual` sandbox mode is set by each `test_helper.exs`, not by the cluster;
4. configures the test repos at boot (the one place `Application.put_env` is allowed, before any repo starts). In `turnstile`: `Turnstile.TestRepos.Sandboxed` (app role, `pool: Ecto.Adapters.SQL.Sandbox`, `socket_dir:`, `turnstile_test`), `Turnstile.TestRepos.Committed` (app role, the default pool, small `pool_size`, `turnstile_committed`), and `Turnstile.TestRepos.Owner`, which is `use Turnstile.Repo, role: :owner` and is what truncation and a committed test's out-of-band writes run through. In a thin app: `Example.Repo` (app role, sandbox pool) and `Example.OwnerRepo` (owner role), the same two modules the thin app runs in production, with the cluster's socket and roles put in their config;
5. registers `ExUnit.after_suite/1` and `System.at_exit/1`, once per VM, to `pg_ctl stop -m immediate` every cluster still running and remove its directory. The suite's end stops its cluster, because a cluster still running holds the repo modules the next one would configure. The root's test step runs each app's suite in an operating-system process of its own (`docs/code.md` §5): the umbrella's own recursion starts every application in one VM before the first suite runs, and the thin applications bind the same repo modules, so one VM cannot hold two of them.

Startup is about a second. Because the socket directory is random, `mix test --partitions N` runs N clusters side by side, and parallel CI jobs cannot collide. The cluster runs with `fsync=off`, which is fine because the suite asserts shapes, not timings (§6).

Inside the run, the SQL Sandbox in `:manual` mode gives each test a connection wrapped in a transaction. `Turnstile.Test.Sandbox.setup/2` is what every case template's `setup` calls:

```elixir
setup tags do
  Turnstile.Test.Sandbox.setup(Turnstile.TestRepos.Sandboxed, tags)
end
```

It starts a sandbox owner for that repo, shared with the processes the test spawns when the test is not async, and registers an `on_exit` that stops the owner. A test tagged `:committed` gets no sandbox: it runs real commits on the committed database and cleans up through the owner-role repo. `Task`s a sandboxed test spawns inherit the connection through `$callers`. `set_config(name, value, true)` is transaction-scoped, so the row-level security session settings the Postgres adapter sets inside `around_query/3` cannot leak between tests. `Repo.transaction` inside a test becomes a savepoint; the seam's own transactions behave as they do in production.

## 4. Cerbos and OpenFGA in tests

The launchers live in `apps/turnstile_dev`, which is never published: starting an operating-system process takes `muontrap`, and an adapter package carries no dependency its own users do not need. An adapter suite takes the package as `{:turnstile_dev, in_umbrella: true, only: :test}`.

`Turnstile.Dev.Cerbos.start_shared/1`, called from `test_helper.exs`, starts one `cerbos server` for the run under `MuonTrap.Daemon` (muontrap 2.0.0, `docs/code.md` §3); it dies when the VM does. It runs with the calling app's policy directory, its audit log written to a file under `tmp/`, listening on a free port of the loopback interface; the address goes into the adapter tuple in the test config. Tier 1 reads `turnstile_cerbos/priv/conformance/`. `example_cerbos` copies `priv/policies/` into a directory under `tmp/` and serves the copy, because a scenario that publishes a rule change writes a policy file into the directory the sidecar watches, and it must be able to do that without changing the working tree. Cerbos serves its HTTP API on a unix socket as readily as on a port, `server.httpListenAddr` taking either a host with a port or a `unix:` path (both run against cerbos 0.55.0 before this was written), and the port is what the suite uses because the adapter's client is Erlang's `httpc`, which has no unix-socket transport.

`Turnstile.Dev.Fga.start_shared/1` is the same shape for `openfga run --datastore-engine memory`: one server per run, on a free port, holding nothing on disk. Isolation inside it is a store per test (§5), which is OpenFGA's own unit. A test that needs no server at all runs against `Turnstile.Fga.Client.Fake`, an `Agent` in `turnstile_fga`'s `test/support`: the drain's convergence, the read-diff-write for a changed condition, and drift between the tables and the store are proved there, and the server is where the decisions are proved.

A test that publishes a policy version, or reconciles against out-of-band writes, starts its own instance: `start_supervised({MuonTrap.Daemon, [...]})`, a temp policy directory or a store of its own, and a wait on the health endpoint through `Turnstile.Test.poll/2`. About a hundred milliseconds; the test is still async, because nothing is shared.

## 5. The async patterns

| Shared thing | Pattern |
|---|---|
| The clock | `%Turnstile.Config{clock}` is a zero-arity function, and the configuration override travels through `$callers`. `Turnstile.Test.Clock.set/1` installs a closure over one moment for the rest of the calling process, so each test sets its own time; production leaves the default, `&DateTime.utc_now/0`. |
| Configuration: the adapter tuple and the caps | Production reads a `%Turnstile.Config{}` once at boot (`docs/reference.md` §14). In tests, `Turnstile.Test.with_config/1` (for the rest of the process) and `with_config/2` (around a function) put an override in the process dictionary; `Turnstile.Config.resolve/0` checks `self()` and then the `$callers` chain. The override carries the adapter tuple, which is how `AdapterCase` binds one per test module and how the FGA `client` module and `store_id` reach the adapter. `Application.put_env` inside a test is banned; it is global. A test that assumes nothing is booted saves the boot term, erases it for its own duration, and puts it back after, in a module that is not async: a suite runs with its own application started, so a boot config and a boot binding exist that a later test in the same VM reads. |
| Telemetry handlers | No test attaches a handler for longer than it needs one. `Turnstile.Test.queries/2` and `Turnstile.Test.changes/1` attach for the duration of one function and drop every event that did not come from the calling process, so two async tests never see each other's. A test that asserts on a decision event routes events to itself with `:telemetry_test.attach_event_handlers/2` and filters by the `operation_id` it passed, ignoring everyone else's. |
| The fake adapter's rule table | `Turnstile.Test.Fake`, an `Agent` per test via `start_supervised`, unnamed, bound through the configuration override. Every fake returns a value of the real type: its `scope` returns a real `dynamic`, its `explain` answers the reason `:unsupported`, and a table told to fail answers `:engine_unreachable`, which is the port's fail-closed path. |
| The fake FGA client | `Turnstile.Fga.Client.Fake`, an `Agent` per test via `start_supervised`, holding stores, models, and tuples, named in `adapter: {Turnstile.Fga, client: ...}` through the override (`docs/reference.md` §12). |
| The OpenFGA store | A store per test, OpenFGA's own isolation unit, with the model published into it in `setup` and its id in the override, so each test's drain starts from an empty store. |
| Library processes: the relay's runner | Startable unnamed, with the repo, the job, and the clock injected; tests never rely on a registered name and never leave a runner ticking: they call `Turnstile.Relay.drain_once/1` themselves. `Turnstile.Test.settle/0` is the one-line form: it settles the configured adapter when that adapter keeps state of its own, and answers `:none` otherwise, so a shared scenario can settle after writing facts without naming an adapter. |
| The Repo's dynamic-repo process dictionary entry | Per process by construction; inherited by Tasks through `$callers`. |
| Time in tests | No `Process.sleep/1` outside `Turnstile.Test.poll/2`, a deadline loop with a fixed interval used for the revocation-latency measurement and for waiting on external processes. Synchronization uses messages. |

## 6. What proves what

Four kinds, and each one has a place it belongs:

| Kind | What it proves | Where |
|---|---|---|
| Conformance suites | A module that touches the world behaves as every other of its kind, and which requests it cannot narrow | `AdapterCase` and `RepoCase` in `turnstile`; `JobCase` in `turnstile_relay`; `OutboxCase`, `GuardCase`, and `TupleMappingCase` in `turnstile_fga` |
| Properties | A decision is right for inputs nobody thought of | The matching rules, the drain, the engine codecs, the banner, and the relay's durability |
| Scenarios | The example obeys its own rules, under every binding | The nine groups of `docs/reference.md` §3a, in the four thin applications |
| Shape tests | The work is the size it should be | Query counts and record counts |

The properties and the suites divide by the rule of `PLAN.md` §2. A property tests a module under `core/`, which decides and touches nothing, so it needs no database. A suite tests a module under `adapter/` against the real database or engine.

**The case templates.** Each is `use`d with the modules it cannot know, and writes the tests itself:

- `Turnstile.Conformance.AdapterCase`, `adapter:`, `repo:`, and `world:`. The port's invariants as `stream_data` properties over `Turnstile.Conformance.Gen`: rule agreement (the adapter answers as the world's rule does), scope fidelity (the rows a scope admits are the objects `check` allows), deny by default (an unknown operation, subject kind, or subject is denied), and batch agreement (`batch` and `filter` agree with `check` object by object); a round trip for `Turnstile.Decision`; the scope cap declaration; the two shape tests; the fail-closed case, when an `outage:` module is given; and the revocation-latency case, when a `committed:` repo is given.
- `Turnstile.Conformance.RepoCase`, `repo:`. The repo answers `__turnstile__/1`, exports nothing outside `Turnstile.Core.Surface`'s list, and refuses every query, write, and raw call on an audited schema that carries no decision and no exemption, before any SQL. With a `rows:` module it gets four more, one per guarantee the change event makes (`docs/reference.md` §7).
- `Turnstile.Relay.JobCase`, `job:`, `repo:`, and `rows:`. The three obligations a runner relies on: a read answers entries above the position it was given, in position order, and no more of them than the limit; positions rise and are unique; and a batch already delivered may be delivered again.
- `Turnstile.Fga.OutboxCase`, `GuardCase`, and `TupleMappingCase`, one per thing a binding declares: the drain against a server and the application's own tables, the guard against every operation and environment the application named, and the mapping against the four laws a drain rests on, with no server at all.
- `Turnstile.Conformance.Case`, the `scenario` macro, which is Tier 2's.

**The neutral fixture.** Tier 1's fixture is `turnstile`'s, under `test/support` rather than `lib`, so the published package carries no population of its own: two object types, two roles, one attribute, one relationship, as Ecto schemas against the same Postgres the rest of the suite uses. Each adapter package carries what the fixture needs on its mechanism in its own `test/support`, under a `Conformance` module of the package's namespace: `turnstile_rbac` the role table and predicates, `turnstile_postgres` the row-level security migration for the fixture tables, `turnstile_cerbos` the attribute declarations, `turnstile_fga` the tuple mapping. What an engine reads as text stays under `priv/conformance/`: the Cerbos policies and the OpenFGA model. The CUI domain appears in none of them. What the template reads the population through is `Turnstile.Conformance.World`, a behaviour in `turnstile`'s `lib`: a module that says what a population holds, what the rule over it allows, and how to write one through the seam. An adapter outside this repository passes its own.

**Tier 2** is `Example.Scenarios`, test support in `example`: every scenario of `docs/reference.md` §3a, declared once and defined in a thin application's one test file by `use Example.Scenarios, rules: ExampleRbac.Rules`. The adapter comes from the thin application's boot config, not from the test file. Each scenario's body is a function named by its id in a module under `Example.Scenarios`, so the sentence and the body are written once and every binding runs both. The macro checks the id and the sentence against `Turnstile.Conformance.Scenarios`, which holds §3a's table as data, and tags the test with its id, its rule, and the controls the table cites. The six scenarios that need real commits are defined in a nested `Committed` module that is not async; the rest run in a sandbox transaction. What a thin application supplies through `Example.Scenarios.Rules` is what a test cannot write without naming the adapter: the telemetry event its adapter publishes a policy version on, a tightened policy and its restoration, and, where the engine keeps state of its own, the per-test setup.

**The count test.** `use Example.Scenarios` ends by defining one more test: the scenario ids defined across the module and its `Committed` submodule are §3a's ids, all of them, and no others. A scenario missing from the module fails it. No binding declares a scenario unsupported and no scenario is skipped, so a green run is a run that answered every row.

**Tags.**

- **Default**: `async: true`, the sandboxed repo. Most of Tier 1 and most of Tier 2.
- **`@tag :committed`**: `async: false`, the committed repo, truncation through the owner-role repo in `setup` and `on_exit`. Only what needs real concurrent commits or a reader on a second connection. In Tier 1: the two connections contending for a runner's lock, a migration taken down and raised again, the drain cases, and the revocation-latency case per adapter. In Tier 2: `rev-01` and `rev-06`, which measure latency; `rvw-04`, whose reconcile runs on the owner-role repo's connection; and `cm-01`, `cm-02`, and `cm-03`, which publish a rule change, since for an adapter whose rules are the database's own that is a schema change, and a schema change waits for every other connection reading the tables it changes.
- **The latency measurement**, one Tier 1 case per adapter from the template and `rev-01` in Tier 2: a revoking fact written through the seam on the committed repo; the monotonic clock read when the transaction returns; `Turnstile.Test.settle/0`, timed where the adapter has state to settle; then `Turnstile.Test.poll/2` until the first denied check; then the clock again. `rev-06` measures propagation from a policy publication the same way. The total, the components, and the poll interval as the floor are printed beside the run; components the environment lacks are printed as not measured. Rule C12 is never asserted; nothing in the suite fails on a latency number.
- **Shape tests** (`docs/reference.md` §7): untagged, sandboxed, async. `Turnstile.Test.queries/2` counts the SQL the calling process ran, transaction control filtered out, and `Turnstile.Test.changes/1` counts the change events it published, so both are exact in the sandbox and cannot flap. An adapter that adds queries of its own to every call declares how many through `setup_queries:`. The engine's own calls are not database queries: each client publishes one telemetry event per call, which is how a shape test counts them.
- **The structure test**, one case in `turnstile_dev`: untagged, async, and over no database. It reads every `.ex` file under each package's `lib` and `test/support` and holds each to the rule `PLAN.md` §2 states, the file's path naming a module the file defines and every other module it defines being named under that one. It reads the syntax tree rather than the compiled modules, so it starts nothing and depends on nothing it reads.

**Committed outputs.** The one output compared against a file in the repository is the schema dump: `mix turnstile.schema_dump` writes `priv/schema/<adapter>.sql`, and CI's `git diff --exit-code` is the assertion (§7). `mneme` is not used: its last release, 0.10.2, is from 2025-01-24, before Elixir 1.20, and it rewrites test source files, which is a second formatter beside Styler. Doctests run everywhere they are cheap and true.

## 7. CI

One workflow, `nix develop` everywhere:

- **quality**: `mix quality` (`docs/code.md` §5): a dependency audit, format, compile with warnings as errors, Credo strict, xref compile-connected and cycles, unused locks, a security advisory audit, docs with warnings as errors, then tests with coverage. Tests run `--partitions 4` across four jobs, each with its own ephemeral cluster, shared Cerbos, and OpenFGA. The runtime dependency count of `turnstile`, the first of `PLAN.md` §5's two numbers, is a test in that package's own suite and runs here.
- **core_coverage**: `mix test.core`, unpartitioned, over every package that has a `core/`. It is the second of the two numbers: every module under a `core/` at 100% line coverage. It runs alone because a partitioned run measures coverage over a part of the suite.
- **example_rbac**, **example_postgres**, **example_cerbos**, **example_fga**: one job per thin app, run in `apps/example_<adapter>/`, in this order:
  1. `mix turnstile.schema_dump` (a task in `turnstile`): an ephemeral cluster, the thin app's migrations as the owner, `pg_dump --schema-only` into `priv/schema/<adapter>.sql`, stop; then `git diff --exit-code priv/schema/`. The Postgres dump is the teaching artifact; the diff is what proves it.
  2. `mix test --warnings-as-errors --cover`, Tier 2 with the count test.

Every app's own coverage threshold is 90%, and warnings are errors in every job. No job uses Docker.

## 8. Not done, on purpose

No Docker anywhere. No shared development database for tests. No `Application.put_env` after boot. No telemetry handler in a test that outlives the function it was attached for. No `:meck` or module-level mocking; behaviours and fakes that answer with the real types. No `Process.sleep` outside the polling helper. No registered process names in library code that a test would need to know. No fake that raises where the real implementation returns. No test that leaves a relay runner ticking; `drain_once/1` is driven. No assertion on a latency number. No test that passes by skipping. No `mneme` (§6).
