# Turnstile: testing
*The environment the suite runs in, how a test owns its state so `async: true` is the default, the tiers and tags, and what CI runs. Decided: Nix for the toolchain and every service, no Docker; an ephemeral Postgres cluster per `mix test` run; a counter row per test so fact-writing tests stay async; shape tests, counts and not timings, on every pull request, and benchmarks on demand.*

## 1. The principle

**Every test owns its state.** Its own database connection, its own clock, its own configuration, its own counter row, its own Cerbos when it changes policies, its own OpenFGA store, its own operation ids, its own processes. Shared mutable globals are what force `async: false`; each one in §5 has a pattern that removes it. `async: false` is a tagged exception with a reason in the tag, never a default.

## 2. Environment: the flake is the pin

`flake.nix` provides the dev shell and the CI environment, from nixpkgs `nixos-unstable` locked in `flake.lock`:

- the toolchain: `beam.packages.erlang_29.elixir_1_20`, which is OTP 29.0.6 and Elixir 1.20.4 on the locked branch, so no overlay is needed;
- `postgresql_18`, written explicitly and never as the bare `postgresql` alias, which is 18 on unstable and 17 on both stable branches;
- `openfga` from nixpkgs, 1.19.0;
- Cerbos 0.55.0, which is in no nixpkgs branch, from its release archive: a `stdenvNoCC` derivation that `fetchurl`s `cerbos_0.55.0_<Linux|Darwin>_<x86_64|arm64>.tar.gz` with a hash per system (Linux x86_64, Linux arm64, Darwin arm64, Darwin x86_64) recorded in the flake;
- all four as binaries on the path, not as services; tests start their own (§3, §4);
- `services-flake` with `process-compose` for day-to-day services: `nix run .#services` brings up its `postgres` service plus Cerbos and OpenFGA as plain process-compose processes wrapping the binaries, since services-flake has no module for either, on local ports for running a thin app by hand;
- `direnv` with `use flake`, so entering the directory is entering the environment.

Each pin, and where it was verified on 2026-09-07 (the full table with URLs is `docs/reference.md` §12):

| Pin | Version | Verified at |
|---|---|---|
| nixpkgs `nixos-unstable` | head `c043004d…`, 2026-09-05 | stable 26.05 has openfga 1.14.2, so unstable is the branch matching every pin at once |
| `beam.packages.erlang_29` | OTP 29.0.6 | `pkgs/development/interpreters/erlang/29.nix` on master and `nixos-unstable` |
| `elixir_1_20` | 1.20.4, minimum OTP 27, maximum OTP 29 | `pkgs/development/interpreters/elixir/1.20.nix` |
| `postgresql_18` | 18.6 | `pkgs/servers/sql/postgresql/18.nix`; the alias default is `all-packages.nix` |
| `openfga` | 1.19.0 | `pkgs/by-name/op/openfga/package.nix`; release published 2026-08-25 on GitHub |
| Cerbos | 0.55.0, published 2026-08-13 | absent from nixpkgs, 404 on every branch; the GitHub release API, asset pattern: tag has `v`, filename does not, OS names capitalized |
| services-flake | active, last commit 2026-08-18 | its repository; no cerbos or openfga service module |

S0 re-verifies every row and says where in its commit message. Nix is not installed on the development Mac; S0 installs it and stops to ask before running the installer. On Darwin the fetched Cerbos binary is unsigned; whether Gatekeeper interferes with a binary that reaches the machine through the Nix store rather than a browser, and what the flake does about it if so (an `xattr -d com.apple.quarantine` step in the derivation, or nothing), is recorded in a comment beside the derivation.

CI runs `nix develop --command mix quality`; dev and CI are the same closure. There is no `docker-compose.yml`, no `.tool-versions`, and no other documented path. S0's gate prints the Cerbos and OpenFGA versions from the packaged binaries: `cerbos --version` printing 0.55.0 and `openfga version` printing 1.19.0.

## 3. The ephemeral cluster

`mix test` does not touch the dev services. `test_helper.exs` in every app calls `Turnstile.Test.Cluster.start/1` (shipped in core under `Turnstile.Test`, so a third party's adapter can run Tier 1 with it; it raises on failure), which:

1. runs `initdb` into `tmp/pg-<random>/` with `--auth=trust`, and `pg_ctl start` with `-k <that dir>` and `-c listen_addresses=''`: a unix socket, no TCP port, nothing to collide with; plus `fsync=off`, `synchronous_commit=off`, `full_page_writes=off` for speed;
2. creates two roles, `turnstile_owner`, which owns the tables and runs migrations, and `turnstile_app`, which does not own them and carries `NOBYPASSRLS`, the shape row-level security needs (`docs/reference.md` §4); and two databases, `turnstile_test` and `turnstile_committed`;
3. runs the migrations the caller names, as the owner, through the `migrate:` function the caller passes, once per database, with an owner-role repo whose dynamic instance points at that database (a thin app passes `Ecto.Migrator` over its own `priv/repo/migrations`; `turnstile_fga`'s checkpoint helper and `turnstile_postgres`'s `priv/conformance/` RLS migration reach the cluster the same way). Core's `lib` depends on `ecto` alone; `ecto_sql` and `postgrex` are its test-only dependencies, and the cluster itself runs `initdb`, `pg_ctl`, and `psql` as commands and calls only `Ecto.Repo` functions, which is why it takes the migration function rather than calling `Ecto.Migrator`. The counter table `turnstile_ledger_counter(name, position)` and its `default` row at 0 come from `turnstile_ledger`'s migration helper everywhere but in core's own run: the ledger depends on core, and the umbrella refuses the cycle even when the other edge is test-only, so core's test support creates the same table with its own statements and the freeze test holds the columns to the committed list. The sandbox helper stays in core's test support, since it is `ecto_sql`, and the `:manual` sandbox mode is set by each `test_helper.exs`, not by the cluster;
4. configures the test repos at boot (the one place `Application.put_env` is allowed, before any repo starts). In core: `Turnstile.TestRepos.Sandboxed` (app role, `pool: Ecto.Adapters.SQL.Sandbox`, `socket_dir:`, `turnstile_test`), `Turnstile.TestRepos.Committed` (app role, the default pool, small `pool_size`, `turnstile_committed`), and `Turnstile.TestRepos.Owner`, which is `use Turnstile.Repo, role: :owner` and is the ledger tuple's `owner_repo` in test config, so reconcile, genesis, the catalog check, and truncation run through it. In a thin app: `Example.Repo` (app role, sandbox pool) and `Example.OwnerRepo` (owner role), the same two modules the thin app runs in production, with the cluster's socket and roles put in their config;
5. registers `ExUnit.after_suite/1` and `System.at_exit/1`, once per VM, to `pg_ctl stop -m immediate` every cluster still running and remove its directory. The suite's end stops its cluster, because a cluster still running holds the repo modules the next one would configure. The root's test step runs each app's suite in an operating-system process of its own (`docs/code.md` §5): the umbrella's own recursion starts every application in one VM before the first suite runs, and the thin applications bind the same repo modules and the same audit store, so one VM cannot hold two of them. The mock clock is defined once per VM for the same reason.

Startup is about a second. Because the socket directory is random, `mix test --partitions N` runs N clusters side by side, and parallel CI jobs cannot collide. The cluster runs with `fsync=off`, which is fine because the suite asserts shapes, not timings (§6); the one tripwire is bounded generously enough not to care.

Inside the run, the SQL Sandbox in `:manual` mode gives each test a connection wrapped in a transaction. `Turnstile.Test.Sandbox.setup/2`, called from every case template's `setup`, does three things in the test process:

```elixir
setup tags do
  Turnstile.Test.Sandbox.setup(Turnstile.TestRepos.Sandboxed, tags)
end

# which is, for a repo and the test's tags:
:ok = Ecto.Adapters.SQL.Sandbox.checkout(repo)
unless tags[:async], do: Ecto.Adapters.SQL.Sandbox.mode(repo, {:shared, self()})
counter = "test-" <> Integer.to_string(System.unique_integer([:positive]))
repo.insert_all("turnstile_ledger_counter", [%{name: counter, position: 0}], turnstile: {:exempt, :library})
Turnstile.Test.with_config(ledger_counter: counter)
```

The counter row is inserted inside the sandbox transaction, so it rolls back with the test and two async tests never contend on `default`; the library exemption is accepted because `Turnstile.Test.Sandbox` is a `Turnstile.*` module. `with_config/1` puts the override in the process dictionary for the rest of the test; the seam's resolver reads it from `self()` and then the `$callers` chain (`docs/code.md` §2). Committed-repo tests skip the row and use `default`.

`Task`s the test spawns inherit the connection through `$callers`. `set_config(name, value, true)` is transaction-scoped, so RLS session settings the Postgres adapter sets inside `around_query/3` cannot leak between tests. `Repo.transaction` inside a test becomes a savepoint; the seam's own transactions, the counter take among them, behave as in production.

## 4. Cerbos in tests

`Turnstile.Test.Cerbos.start_shared/1`, also from `test_helper.exs`, starts one `cerbos server` for the run under `MuonTrap.Daemon` (muontrap 2.0.0, a new major whose API S0 checks, `docs/code.md` §3); it dies when the VM does. It runs with the calling app's policy directory (`turnstile_cerbos/priv/conformance/` for Tier 1, `example_cerbos/priv/policies/` for Tier 2), its audit log written to a file under `tmp/`, listening on a unix socket where the client supports it and otherwise a free local port ⟨verify⟩; the address goes into the adapter tuple in the test config. Decision tests are read-only against it and stay async.

A test that publishes a policy version, or reconciles the decision log, starts its own instance: `{:ok, _} = start_supervised({MuonTrap.Daemon, ["cerbos", "server", "--config", tmp_conf]})`, a temp policy directory, a wait on the health endpoint through `Turnstile.Test.poll/2`. About a hundred milliseconds; the test is still async, because nothing is shared.

## 5. The async patterns

| Shared thing | Pattern |
|---|---|
| The clock | `Turnstile.Clock` is a behaviour. Tests use `Mox`, which is `$callers`-aware; each test sets its own time; production uses the real clock module named in `%Turnstile.Config{clock}`. |
| Configuration: the adapter tuple, the ledger tuple, the counter name, caps | Production reads a `%Turnstile.Config{}` once at boot. In tests, `Turnstile.Test.with_config/1` (for the rest of the process) and `with_config/2` (around a function) put an override in the process dictionary; the seam's resolver checks `self()` and then the `$callers` chain. The override carries the adapter tuple, which is how `AdapterCase` binds one per test module and how the FGA `client` module and `store_id` reach the adapter; and the counter name, set by the sandbox setup. `Application.put_env` inside a test is banned; it is global. A test that assumes nothing is booted saves the boot term, erases it for its own duration, and puts it back after, in a module that is not async: a suite runs with its own application started, so a boot config and a boot binding exist that a later test in the same VM reads. |
| Telemetry handlers | No test attaches a global handler. Every decision and fact event carries an `operation_id`; the test performs its operations and asserts on its own ids, `assert_decision(operation_id, verdict: :deny, reason: %NotAssigned{})`, ignoring everyone else's events. `:telemetry_test.attach_event_handlers/2` is used only to route events to the test process; filtering is by id. |
| The in-memory ledger and the fake adapter's rule table | An `Agent` per test via `start_supervised`, unnamed, passed through the config override. Every fake returns a value of the real type: the fake adapter's `scope` returns a real `dynamic`, its `explain` returns `{:error, %Turnstile.Error.Unsupported{}}`. |
| The fake FGA client | `Turnstile.Fga.Client.Fake`, an `Agent` per test via `start_supervised`, holding stores, models, and tuples, named in `adapter: {Turnstile.Fga, client: ...}` through the override (`docs/reference.md` §13). |
| The OpenFGA store | A store per test (`CreateStore`), FGA's own isolation unit, with the model published into it in `setup` and its id in the override; the projector's checkpoint is keyed by store id, so each test's checkpoint starts at zero. |
| Library processes: the reconcile scheduler and the projector | Startable unnamed, with injected repo, ledger, clock, and client; tests never rely on a registered name and never start the projector process: they call `drain_once/1` themselves. `Turnstile.Test.settle/0` is the one-line form: `drain_once/1` to the head when the configured adapter declares a projection, a no-op otherwise, so a shared scenario can say "settle" after writing facts without naming an adapter. |
| The ledger's positions | Each async test takes positions from its own counter row (§3); positions taken inside a rolled-back sandbox transaction are rolled back with it, so a test may assert contiguity within its own run. Committed-repo tests use `default`. |
| The Repo's dynamic-repo process dictionary entry | Per process by construction; inherited by Tasks through `$callers`. |
| Time in tests | No `Process.sleep/1` outside `Turnstile.Test.poll/2`, a deadline loop with a fixed interval used for the revocation-latency measurement and for waiting on external processes. Synchronization uses messages. |

## 6. Tiers and tags

- **Default**: `async: true`, the sandboxed repo, a counter row per test. Most of Tier 1 and most of Tier 2.
- **`@tag :committed`**: `async: false`, the committed repo, truncation through the owner-role repo in `setup` and `on_exit` (the domain tables, the events table, the `default` counter row reset to 0, the checkpoint table). Only what needs real concurrent commits or a reader on a second connection. In Tier 1: the interleaved-transactions case and the lock-cost measurement (`docs/reference.md` §9), the append-only grant, reconcile against out-of-band writes that must be visible to a second connection, the three projection cases driving `drain_once/1`, and the revocation-latency case per adapter. In Tier 2: `rev-01` and `rev-06`, which measure latency, and `rvw-04`, whose reconcile runs on the owner-role repo's connection. In core the committed repo is `Turnstile.TestRepos.Committed`; in a thin app the committed scenario checks `Example.Repo` out with `sandbox: false`, so the same module serves both.
- **The latency measurement**, one Tier 1 case per adapter from the template in core and `rev-01` in Tier 2: a revoking fact written through the seam on the committed repo; `System.monotonic_time(:millisecond)` read when the transaction returns; for an adapter that declares a projection, one `drain_once/1`, timed as `projector_drain`; then `Turnstile.Test.poll/2` against the port until the first denied check; then the clock again. `rev-06` measures `policy_propagation` from a policy publish the same way. The total, the components, and the poll interval as the floor are printed to the log; components the environment lacks (`replica_lag`, `cache`) are printed "not measured". C12 is never asserted; nothing in the suite fails on a latency number.
- **Shape tests** (`docs/reference.md` §7): untagged, sandboxed, async. They count queries through Ecto's `[:repo, :query]` telemetry with transaction-control statements filtered out (the Postgres adapter's `set_config` statement counts as one), plus audit records and ledger rows, so they are exact in the sandbox and cannot flap. Counts are stated per adapter and per ledger mode. Fixtures are a thousand rows, or one batch plus one. The atomicity case forces a ledger append to fail and asserts the write rolled back.
- **`@tag :tripwire`**: one test, `async: false`, the committed repo: the 5,000-row `bulk_update` under ten seconds. Order-of-magnitude protection only.
- **`mix turnstile.bench`**: Benchee, on demand, output committed to the docs as a table; the counter row's serialization cost is among its measurements. Never a gate.
- **`@tag :cerbos`**, **`@tag :postgres`**, **`@tag :fga`**: filtering only; everything runs by default because the shell always has all three.

**The neutral fixture**. Tier 1's fixture is core's: two object types, two roles, one attribute, one relationship, as Ecto schemas against the same Postgres the rest of the suite uses. Each adapter package ships what the fixture needs on its mechanism under `priv/conformance/`: `turnstile_rbac` the role table and predicates, `turnstile_postgres` the RLS migration for the fixture tables, `turnstile_cerbos` the policies, `turnstile_fga` the model and a tuple mapping module. The CUI domain appears in none of them.

**Tier 1** is a case template, `use Turnstile.Conformance.AdapterCase, adapter: Turnstile.Code`, the property suite core ships; it passes the adapter through the config override, so each adapter's conformance run is its own async module, all four run in one `mix test`, and a third party's adapter runs the same template. Property tests with `stream_data`, generators in `Turnstile.Conformance.Gen`, cover the laws rather than examples: scope fidelity (`rows(scope) == filter(check)` over random subjects and objects), deny by default (an unknown operation or subject kind is always denied), record-then-erase, batch agreement, fold-then-replay (fold of appended events equals state; replay at *t* equals the fold stopped at *t*), and `to_map`/`from_map` round trips for every struct with an edge. The seam sweep is `Turnstile.Conformance.RepoCase`, which diffs `Turnstile.Repo.Surface`'s list against a Repo's exported functions; core runs it against the test repos and every thin app runs it against its own Repo; its explicit cases are listed in `docs/reference.md` §6.

**OpenFGA in tests.** One `openfga run --datastore-engine memory` per run, started from `test_helper.exs` under `MuonTrap.Daemon` beside the shared Cerbos; a store per test (§5). The client behaviour's fake, `Turnstile.Fga.Client.Fake`, is where the projector's unit tests and the tuple mapping's tests run: convergence of a re-drain, drift between the fold and `Read`, the read-diff-write for a decontrol change, and duplicate or missing writes rejected atomically, all without a server. The real server is where decisions are proven: the Tier 1 projection cases on the committed repo (measured lag, drift from a tuple deleted through the client, a re-drain after a simulated crash, `docs/reference.md` §13) and Tier 2 under `example_fga`. The projector under test drains from the ledger through `drain_once/1`, from the committed ledger in the projection cases and from the sandbox connection, which sees its own uncommitted events, when `Turnstile.Test.settle/0` runs inside a sandboxed scenario.

**Tier 2** is `Example.Scenarios`, test support in `turnstile_example`: every scenario in `docs/reference.md` §3a, declared with the `scenario` macro (`Turnstile.Conformance.Case`) as `scenario "enf-01", "<sentence>", control: [...], rule: :c1 do ... end`. `use Example.Scenarios, capabilities: ExamplePostgres.Capabilities` in a thin app's one test file defines all of them in that module; the adapter comes from the thin app's boot config, not from the test file. At expansion the macro tags the test with its rule, its controls, and the capability record the declaration returns, and, for an `unsupported` rule, emits the skip with the declaration's note as the reason. A scenario marked `ledger` in §3a carries `needs_ledger: true`, and `test_helper.exs` excludes that tag when the boot config's ledger is `:none`, so its skip reason is `needs_ledger`. `@tag :committed` before a `scenario` call works as it does before `test`, because the macro expands to one. `example_rbac`'s job runs the whole module twice, once with `EXAMPLE_LEDGER=ecto` and once with `EXAMPLE_LEDGER=none`, the variable read by its `config/test.exs` into the boot config; the other three thin apps run mode Ecto.

**The count test**. `use Example.Scenarios` ends by defining one more test: the number of scenarios defined without a skip equals the rows of `docs/reference.md` §3a, minus those whose rule the declaration marks `unsupported`, minus, when the boot config's ledger is `:none`, those marked `ledger`, and is greater than zero. A skip for any other reason, or a scenario missing from the module, fails it. A green run of skipped scenarios is a failure.

**Golden files.** Where an output is text (the schema dump, `mix turnstile.review`'s table, an `explain`), the test is a plain assertion against a committed file; `TURNSTILE_UPDATE_GOLDEN=1 mix test` rewrites them, and the diff is reviewed like any other. `mneme` is not used: its last release, 0.10.2, is from 2025-01-24, nineteen months before this plan and before Elixir 1.20, and it rewrites test source files, which is a second formatter beside Styler. Doctests run everywhere they are cheap and true.

## 7. CI

One workflow, `nix develop` everywhere:

- **quality**: `mix quality` (`docs/code.md` §5): format, compile with warnings as errors, Credo strict, xref cycles, dependency hygiene, docs, then tests with coverage. Tests run `--partitions 4` across four jobs, each with its own ephemeral cluster, shared Cerbos, and OpenFGA; shape tests and the tripwire included, benchmarks not.
- **example_rbac**, **example_postgres**, **example_cerbos**, **example_fga**: one job per thin app, run in `apps/example_<adapter>/`, in this order:
  1. `mix turnstile.schema_dump` (a task in `turnstile_ledger`): an ephemeral cluster, the thin app's migrations as the owner, `pg_dump --schema-only` into `priv/schema/<adapter>.sql`, stop; then `git diff --exit-code priv/schema/`. The Postgres dump is the teaching artifact; the diff is what proves it.
  2. `mix test`, Tier 2 with the count test.
  For `example_rbac`, step 2 runs twice: with `EXAMPLE_LEDGER=ecto` and with `EXAMPLE_LEDGER=none`.

Coverage threshold and warnings-as-errors apply to every job. No job uses Docker.

## 8. Not done, on purpose

No Docker anywhere. No shared development database for tests. No `Application.put_env` after boot. No global telemetry handlers in tests. No `:meck` or module-level mocking; behaviours and Mox. No `Process.sleep` outside the polling helper. No registered process names in library code that a test would need to know. No fake that raises where the real implementation returns. No test that starts the projector process; `drain_once/1` is driven. No assertion on a latency number. No test that passes by skipping. No `mneme` (§6). 
