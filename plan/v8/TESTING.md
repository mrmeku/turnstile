# Turnstile — testing
*Mode: Reference. The environment the suite runs in, how a test owns its state so `async: true` is the default, the tiers and tags, and what CI runs. Decided: Nix for the toolchain and every service, no Docker; an ephemeral Postgres cluster per `mix test` run; shape tests — counts, not timings — run on every pull request, and benchmarks run on demand.*

## 1. The principle

**Every test owns its state.** Its own database connection, its own clock, its own configuration, its own Cerbos when it changes policies, its own event ids, its own processes. Shared mutable globals are what force `async: false`; each one below has a pattern that removes it. `async: false` is a tagged exception with a reason in the tag, never a default.

## 2. Environment: the flake is the pin

`flake.nix` provides the dev shell and CI environment:

- the toolchain — `beam.packages.erlang_28.elixir_1_20` from a locked nixpkgs, with an overlay if the pin lags the patch release CODE.md names ⟨verify⟩;
- `postgresql` (17 ⟨choose⟩), `cerbos`, and `openfga` ⟨verify nixpkgs⟩, as binaries on the path — not as services; tests start their own (§3, §4);
- `services-flake` with `process-compose` for day-to-day dev services: `nix run .#services` brings up a Postgres and a Cerbos sidecar on local ports for running the example by hand;
- `direnv` with `use flake`, so entering the directory is entering the environment.

CI runs `nix develop --command mix quality`; dev and CI are the same closure. There is no `docker-compose.yml`, no `.tool-versions`, and no other documented path. The Cerbos version the flake pins is the one the adapter's inventory item prints.

## 3. The ephemeral cluster

`mix test` does not touch the dev services. `test_helper.exs` in every app calls `Turnstile.Test.Cluster.start!/0` (test support in core), which:

1. runs `initdb` into `tmp/pg-<random>/` with `--auth=trust`, and `pg_ctl start` with `-k <that dir>` and `-c listen_addresses=''` — a unix socket, no TCP port, nothing to collide with — plus `fsync=off`, `synchronous_commit=off`, `full_page_writes=off` for speed;
2. creates two roles — `turnstile_owner`, which owns the tables and runs migrations, and `turnstile_app`, which does not own them and has `NOBYPASSRLS`, which is the shape row-level security needs (REFERENCE §4) — and two databases, `turnstile_test` and `turnstile_committed`;
3. runs migrations as the owner with `Ecto.Migrator`;
4. configures the three test repos at boot (this is the one place `Application.put_env` is allowed, before any repo starts): `Turnstile.TestRepos.Sandboxed` (app role, `pool: Ecto.Adapters.SQL.Sandbox`, `socket_dir:`), `Turnstile.TestRepos.Committed` (app role, the default pool, small `pool_size`, the second database), `Turnstile.TestRepos.Owner` (for truncation and fixtures);
5. registers `System.at_exit/1` to `pg_ctl stop -m immediate` and remove the directory.

Startup is about a second. Because the socket directory is random, `mix test --partitions N` runs N clusters side by side, and parallel CI jobs cannot collide. The cluster runs with `fsync=off`, which is fine because the suite asserts shapes, not timings (§6); the one tripwire is bounded generously enough not to care.

Inside the run, the SQL Sandbox in `:manual` mode gives each test a connection wrapped in a transaction:

```elixir
setup tags do
  pid = Ecto.Adapters.SQL.Sandbox.start_owner!(Turnstile.TestRepos.Sandboxed, shared: not tags[:async])
  on_exit(fn -> Ecto.Adapters.SQL.Sandbox.stop_owner(pid) end)
  :ok
end
```

`Task`s the test spawns inherit the connection through `$callers`. `SET LOCAL` is transaction-scoped, so RLS session settings set by the seam cannot leak between tests. `Repo.transaction` inside a test becomes a savepoint; the seam's own transactions behave as in production.

## 4. Cerbos in tests

`Turnstile.Test.Cerbos.start_shared!/0`, also from `test_helper.exs`, starts one `cerbos server` for the run under `MuonTrap.Daemon` — it dies when the VM does — with the example's policy directory, its audit log written to a file under `tmp/`, listening on a unix socket where the client supports it and otherwise a free local port ⟨verify⟩; the address goes into the adapter's test config. Decision tests are read-only against it and stay async.

A test that publishes a policy version, or reconciles the decision log, starts its own instance: `start_supervised!({MuonTrap.Daemon, ["cerbos", "server", "--config", tmp_conf]})`, a temp policy directory, a wait on the health endpoint. About a hundred milliseconds; the test is still async, because nothing is shared.

## 5. The async patterns

| Shared thing | Pattern |
|---|---|
| The clock | `Turnstile.Clock` is a behaviour. Tests use `Mox`, which is `$callers`-aware; each test sets its own time; production uses the real clock module bound at boot. |
| Configuration — seam mode, ledger mode, caps, adapter address | Production reads a `%Turnstile.Config{}` once at boot. In tests, `Turnstile.Test.with_config(overrides, fn -> ... end)` puts an override in the process dictionary; the seam's resolver checks `self()` and then the `$callers` chain. `Application.put_env` inside a test is banned — it is global. |
| Telemetry handlers | No test attaches a global handler. Every decision and fact event carries an `operation_id`; the test performs its operations and asserts on its own ids — `assert_decision(operation_id, verdict: :deny, reason: %NotAssigned{})` — ignoring everyone else's events. `:telemetry_test.attach_event_handlers/2` is used only to route events to the test process; filtering is by id. |
| The in-memory ledger and the fake adapter's rule table | An `Agent` per test via `start_supervised!`, unnamed, passed through the config override. |
| Library processes — the reconcile scheduler | Startable unnamed, with injected repo, ledger, and clock; tests never rely on a registered name. |
| The ledger's positions | Sequence values consumed inside a rolled-back sandbox transaction are simply gaps; nothing asserts contiguity. |
| The Repo's dynamic-repo process dictionary entry | Per process by construction; inherited by Tasks through `$callers`. |
| Time in tests | No `Process.sleep/1` outside `Turnstile.Test.poll/2`, a deadline loop used for revocation-latency measurement and for waiting on external processes. Synchronization uses messages. |

## 6. Tiers and tags

- **Default** — `async: true`, the sandboxed repo. Most of Tier 1 and all of Tier 2.
- **`@tag :committed`** — `async: false`, the committed repo, truncation by the owner in `setup`. Only what needs real concurrent commits: the interleaved-transactions case for the visibility-safe reader, the append-only grant, reconcile against out-of-band writes that must be visible to a second connection.
- **Shape tests** (REFERENCE §7) — untagged, sandboxed, async. They count queries through Ecto's `[:repo, :query]` telemetry with transaction-control statements filtered out, plus audit records and ledger rows, so they are exact in the sandbox and cannot flap. Fixtures are a thousand rows, or one batch plus one. The atomicity case forces a ledger append to fail and asserts the write rolled back.
- **`@tag :tripwire`** — one test, `async: false`, the committed repo: the 5,000-row `bulk_update` under ten seconds. Order-of-magnitude protection only.
- **`mix turnstile.bench`** — Benchee, on demand, output committed to the docs as a table. Never a gate.
- **`@tag :cerbos`**, **`@tag :postgres`**, **`@tag :fga`** — filtering only; everything runs by default because the shell always has all three.

OpenFGA in tests: one `openfga run --datastore-engine memory` per run, started from `test_helper.exs` under `MuonTrap.Daemon` beside the shared Cerbos; a **store per test** (`CreateStore`), which is FGA's own isolation unit, so decision and projection tests stay async; the model published into each store from `priv/fga/model.fga` in `setup`. The projector under test drains from the sandboxed ledger into the test's store.

Tier 1 is a case template — `use Turnstile.Conformance.AdapterCase, adapter: Turnstile.Code` — so each adapter's conformance run is its own async module, and a third party's adapter runs the same template. Property tests with `stream_data`, generators in `Turnstile.Conformance.Gen`, cover the laws rather than examples: scope fidelity (`rows(scope) == filter(check)` over random subjects and objects), deny by default (an unknown operation or subject kind is always denied), fold-then-replay (fold of appended events equals state; replay at *t* equals the fold stopped at *t*), and `to_map`/`from_map` round trips for every struct with an edge.

Generator output is tested two ways: the committed statement per example tag, which CI regenerates and diffs (the plan's open 3), and `mneme` auto-assertions for the smaller outputs — POA&M rows, CRM rows, a single control's statement. Doctests run everywhere they are cheap and true.

## 7. CI

One workflow, `nix develop` everywhere:

- **quality** — `mix quality` (CODE.md §5): format, compile with warnings as errors, Credo strict, xref cycles, dependency hygiene, docs, then tests with coverage. Tests run `--partitions 4` across four jobs, each with its own ephemeral cluster and shared Cerbos; shape tests and the tripwire included, benchmarks not.
- **tags** — for each example tag `v0`…`v10b`: check out, regenerate the statement, diff against the committed one. Fails on drift.
- **sources** — on a pinned-source bump: the lint's diff must be committed with the bump (REFERENCE §12).

Coverage threshold and warnings-as-errors apply to every job. No job uses Docker.

## 8. Not done, on purpose

No Docker anywhere. No shared development database for tests. No `Application.put_env` after boot. No global telemetry handlers in tests. No `:meck` or module-level mocking — behaviours and Mox. No `Process.sleep` outside the polling helper. No registered process names in library code that a test would need to know.
