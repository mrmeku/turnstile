# Turnstile: delivery
*Mode: How-to. The stages that build v9, one at a time, and the gate that ends each one as a command and its expected output. You are the agent running a stage.*

## 1. The checkpoint

Before S0 starts, the owner reads `PLAN.md`, `docs/reference.md`, `docs/testing.md`, `docs/code.md`, `docs/writing.md`, and this file, and approves them or edits them. That is the one pause. After it, the stages below run to completion in the order §4 gives, each gated, with a report at the end or when a gate fails. A stage stops for the owner in two cases only: its gate fails and the fix changes something the plan decided, or it needs an admin action on the machine, which for v9 is S0's Nix installer. A question to the owner carries its preamble inside the question text.

## 2. How a stage runs

1. Read `CLAUDE.md` and the files it lists, then the stage's entry below. Read nothing else unless the stage needs it.
2. Work on `main`, no worktree, no branch. Nothing runs beside you; the stages are sequential, and shards inside a stage (S2a, S2b, S2c; S8a, S8b; S9a, S9b; S10a, S10b, S10c) are stages of their own with their own gate and commits.
3. Every command in this file runs inside `nix develop --command` from the directory the gate names; "green" means exit 0 with `warnings_as_errors`. The prompt `$` marks a command; the lines after it are what it must print, where a line in angle brackets describes the output rather than quoting it.
4. Run the stage's gate.
5. Run the prose gate from `CLAUDE.md` over every document you changed.
6. Commit, unsigned, one idea per commit. The last commit message quotes every gate command and its output verbatim, then what the stage's **Record** item asks for, then anything the next stage needs that this file does not say:

```
$ git -c commit.gpgsign=false commit -F -
```

A gate that fails is not worked around: report what failed and stop, and the owner decides whether the stage is rerun or the plan changes.

## 3. The stages

Each stage lists its entry condition, what it delivers, its gate, and, where there is one, what its last commit message must record beyond the gate output.

### S0. Toolchain: the flake and the ephemeral cluster

- **Entry.** The checkpoint passed.
- **Deliverables.** `flake.nix`, `flake.lock`, `.envrc` at the root (`docs/testing.md` §2): `beam.packages.erlang_29.elixir_1_20`, `postgresql_18`, `openfga` from nixpkgs, Cerbos 0.55.0 as a `fetchurl` derivation with a hash per system, `services-flake` with `nix run .#services`. The umbrella root `mix.exs` with the `quality` alias (`docs/code.md` §5) and `apps/turnstile_core` holding `mix.exs`, `test/test_helper.exs`, and test support only: `Turnstile.Test.Cluster.start/1` with its `migrate:` option (`docs/testing.md` §3), `Turnstile.Test.Cerbos.start_shared/1` and `Turnstile.Test.Fga.start_shared/1` under `MuonTrap.Daemon` (§4, §6), `Turnstile.TestRepos.Sandboxed`, `Committed`, and `Owner`, `Turnstile.Test.Sandbox.setup/2` without the counter row for now, `Turnstile.Test.poll/2`. `ecto_sql` and `postgrex` as core's test-only dependencies. `.github/workflows/ci.yml` with the `quality` job installing Nix and running `nix develop --command mix quality` with `--partitions 4`. One smoke test: `SELECT 1` through the sandboxed repo over the socket, `turnstile_app` carries `NOBYPASSRLS`, the socket directory is gone after exit. Nix itself: it is not installed on the development Mac; stop and ask, with a preamble, before running the installer, since it needs the owner's password.
- **Gate.** In `apps/turnstile_core`:

```
$ mix deps.get && mix test
<the smoke test>, 0 failures
$ ls -d tmp/pg-* 2>/dev/null | wc -l
0
$ cerbos --version
<a line containing 0.55.0>
$ openfga version
<a line containing 1.19.0>
$ elixir --version
<Erlang/OTP 29 ... Elixir 1.20.4>
$ postgres --version
<postgres (PostgreSQL) 18.6>
$ git ls-files .tool-versions docker-compose.yml
<nothing>
```

At the root, `nix run .#services` brings up Postgres, Cerbos, and OpenFGA and is stopped by hand; the commit message says it did.
- **Record.** Every row of `docs/testing.md` §2's pin table re-verified, with where; whether Gatekeeper interfered with the fetched Cerbos binary and what the derivation does about it, copied as a comment beside the derivation; the `MuonTrap.Daemon` options used, against muontrap 2.0.0's documentation; the Nix installer used and its version.

### S1. Contracts: the frozen interfaces

- **Entry.** S0.
- **Deliverables.** In `apps/turnstile_core`, empty of mechanism: `Turnstile.Adapter` with `authorize`, `check`, `batch`, `scope`, and `explain` optional; the structs `Subject`, `Object`, `Decision` with `head_position` and `applied_position`, `Reason`, `PolicyVersion`, `%Turnstile.FactEvent{}` with its payload and kinds, `%Turnstile.Exemption{kind: :declared | :library}`; `Turnstile.Clock`, `Turnstile.Ledger`, `Turnstile.Projection` with `rebuild/1` and the checkpoint; the `around_query/3` callback; `use Turnstile.Schema` with `object_type/1`, `carries/1`, `fact/2`, `relationship/1` as declarations that record and do nothing else; `%Turnstile.Config{}` as a `NimbleOptions` schema with the fields of `docs/code.md` §2 and `Turnstile.Test.with_config/1,2` reading it from the process dictionary and `$callers`; `Turnstile.Adapter.Fake` and `Turnstile.Ledger.Memory` returning values of the real type; `Turnstile.Conformance.Case` and `AdapterCase` as `use`-able stubs with the signatures of `docs/reference.md` §14; the `results.json` schema of §12 as a module with a `@typedoc`; the scenario table of §3a as the file the lint reads; the counter row added to `Turnstile.Test.Sandbox.setup/2`. `apps/turnstile_ledger` with the counter table migration helper and `mix turnstile.schema_dump` (`docs/testing.md` §7), and nothing else, so the sandbox row has a table and the thin apps can dump their schema from S3. `boundary` in core with the top-layer rule. Core's glossary and `docs/glossary-index.md` started.
- **Gate.** In `apps/turnstile_core` and then at the root:

```
$ mix quality
<green>
$ mix test --only freeze
<the freeze tests>, 0 failures
$ mix xref graph --format cycles --fail-above 0
<no cycles>
```

The freeze tests enumerate `Turnstile.Adapter.behaviour_info(:callbacks)`, `Turnstile.Ledger.behaviour_info(:callbacks)`, `Turnstile.Projection.behaviour_info(:callbacks)`, the fields of `%Turnstile.FactEvent{}`, `%Turnstile.Exemption{}`, `%Turnstile.Decision{}`, and `%Turnstile.Config{}`, the columns of `turnstile_ledger_counter`, the keys of `results.json`, and the scenario ids of §3a, each against a committed list. From S1 on, changing any of those lists means changing `PLAN.md` or `docs/reference.md` first, in its own commit, and then the list.
- **Record.** The URL of the Elixir 1.20 changelog entry each claim in `docs/code.md` §1 rests on; that `boundary` 0.10.4 compiles under Elixir 1.20.4 with warnings as errors; that core's `lib` compiles with `ecto` alone and the umbrella's shared `deps/` keeps `ecto_sql` out of it.

### S2a. The seam

- **Entry.** S1.
- **Deliverables.** `use Turnstile.Repo`: `Turnstile.Repo.Surface` classifying every `Ecto.Repo` function into query, write, raw, and plumbing; the `@after_compile` exhaustiveness check; the decision-to-query matching rules of `docs/reference.md` §6; exemptions per call, with `Turnstile.Error.Unmediated` on refusal; `around_query/3` as the fourth extension point; the fact-recording hook with the locked re-read for old values and the upsert refusal on fact schemas; the `turnstile:` option schema; `Turnstile.Credo.NoRawSQL` and `UnmediatedRepo`; the seam sweep generated from `Repo.__info__(:functions)` and the explicit cases of §6.
- **Gate.** In `apps/turnstile_core`:

```
$ mix quality
<green>
$ mix test test/turnstile/repo
<the seam sweep and cases>, 0 failures
```

Among the cases: a Repo module compiled in the test with one extra public function raises a `CompileError` naming that function; an upsert on a fact schema raises with the schema's name; a query with no decision raises `Turnstile.Error.Unmediated`.

### S2b. The fake adapter, the in-memory ledger, and Tier 1

- **Entry.** S2a.
- **Deliverables.** `Turnstile.Adapter.Fake` with an `Agent` rule table per test; `Turnstile.Ledger.Memory` complete; `Turnstile.Conformance.AdapterCase` with the properties of `docs/testing.md` §6 (scope fidelity, deny by default, record-then-erase, batch agreement, fold-then-replay, `to_map` and `from_map` round trips), the fail-closed and deny-by-default cases, the shape tests of `docs/reference.md` §7 that need no Ecto ledger, the three projection cases gated on a declared projection, and the latency case template; `Turnstile.Conformance.Gen`; the neutral fixture of §14 as Ecto schemas in core's test support.
- **Gate.** In `apps/turnstile_core`:

```
$ mix quality
<green>
$ mix test --only committed
<the latency template and the committed cases>, 0 failures
```

`mix test` runs `AdapterCase` against `Turnstile.Adapter.Fake`, and the fake's latency case prints its measurement to the log without asserting it. Coverage is at or above 90.

### S2c. The generator skeleton

- **Entry.** S2b.
- **Deliverables.** `apps/turnstile_assess`: `priv/sources.exs` with the pinned files of `docs/reference.md` §12 and a `Turnstile.Conformance.Sources` implementation over them; `Turnstile.Conformance.Scenario` and `LanguageLint`; `Turnstile.Assess.Formatter` writing `results.json`; `mix turnstile.assess` with the Rev 5 markdown profile, printing every control "unknown" when no results exist, `--check` running the skipped-scenario invariant alone, `--citations`; `mix turnstile.review` as a stub that prints "not available before S11"; the golden-file tests under `test/golden/`.
- **Gate.** In `apps/turnstile_assess`:

```
$ mix quality
<green>
$ mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter && test -s tmp/results.json && echo written
<the tests>, 0 failures
written
$ mix turnstile.assess --check
<fails: results.json has zero executed scenarios>; echo "exit=$?" prints exit=1
$ mix turnstile.assess
<a statement in which every baseline control reads "unknown">
```

A test asserts the lint rejects a scenario citing `AC-99` and one citing a control outside the Moderate baseline.

### S4. Rules in code: `turnstile_code`

S4 runs before S3, because `example_code` binds this adapter and cannot enforce without it. The stage numbers are the plan's.

- **Entry.** S2c.
- **Deliverables.** `apps/turnstile_code`: declared roles and permissions as data, attribute predicates, `explain` naming the clause, a policy-version event at boot when the ledger head names an older version, the adapter's domain-free declaration, `priv/conformance/` with the role table and predicates for the neutral fixture.
- **Gate.** In `apps/turnstile_code`:

```
$ mix quality
<green>
$ ls priv/conformance
<the role table and predicate files>
```

`mix test` runs `use Turnstile.Conformance.AdapterCase, adapter: Turnstile.Code` and the latency case prints its measurement.

### S3. The example: `turnstile_example` and `example_code`

- **Entry.** S4.
- **Deliverables.** `apps/turnstile_example`, a library app: the CUI schemas with Portion, `use Turnstile.Schema` declarations on every entity that carries a fact, the contexts, the redacted read (`read_redacted`), the hash-chained audit store, `Example.Repo` and `Example.OwnerRepo` under `use Turnstile.Repo`, the router, controllers, the identity-only plug, the role table with privileged and non-privileged roles on separate accounts, the audited override, re-authentication, fixtures, `Example.Migrations.Domain`, the example's glossary, and `Example.Scenarios` with every scenario of `docs/reference.md` §3a present. `apps/example_code`: its `config/` with `EXAMPLE_LEDGER` read by `config/test.exs` and set to `none` for this stage, `Application.start/2`, the binding to `Turnstile.Code`, `ExampleCode.Capabilities` as function clauses, `priv/repo/migrations` calling the domain helper and the counter helper, `priv/schema/code.sql`, the test file `use Example.Scenarios, capabilities: ExampleCode.Capabilities`, the README with the translation table, and `statement/` regenerated. The seam enforces from the first commit.
- **Gate.** In `apps/example_code`, with `EXAMPLE_LEDGER=none`:

```
$ mix quality
<green>
$ mix turnstile.schema_dump && git diff --exit-code priv/schema/
<nothing>; echo "exit=$?" prints exit=0
$ TURNSTILE_RESULTS=tmp/results-none.json mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter
<the scenarios>, 0 failures, <n> skipped
$ TURNSTILE_RESULTS=tmp/results-none.json mix turnstile.assess && git diff --exit-code statement/statement.md
<nothing>; exit=0
```

That is the first statement, in ledger mode none. Every skip in `results-none.json` reads `needs_ledger` or names a declared capability; the executed count equals the scenario count minus those. In `apps/turnstile_example`, `mix quality` is green and `mix sobelow --config --exit` passes. At the root, `mix quality` is green.
- **Record.** Whether `Example.Repo` in the library app compiled cleanly under the thin app's `config_path`. If not, the fallback is each thin app owning its Repo with the contexts taking a repo argument, and `PLAN.md` §Packages and `docs/testing.md` §3 change to say so.

### S6. The ledger

- **Entry.** S3.
- **Deliverables.** `apps/turnstile_ledger` complete: the events table and its migration helper with the append-only grant, the genesis helper, `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, and `bulk_insert/3` with the null-safe difference condition, `Dialect.Postgres` with the counter take as one `UPDATE ... RETURNING` and `Dialect.Generic`, the reader, reconcile and drift, replay as fold plus policy version, the catalog check for cascading foreign keys into fact schemas, and the ledger's conformance case.
- **Gate.** In `apps/turnstile_ledger`:

```
$ mix quality
<green>
$ mix test --only committed
<the interleaved-transactions case, the lock-cost measurement, the append-only grant, reconcile>, 0 failures
$ mix test --only tripwire
1 test, 0 failures
```

The shape tests of `docs/reference.md` §7 pass with exact counts per dialect; the atomicity case forces a ledger append to fail and asserts the write rolled back; the catalog check fails a migration that adds a cascading foreign key into a fact schema and names the constraint; the fold-then-replay property holds over the bulk API. The lock-cost measurement is printed, never asserted.

### S7. History: `example_code` in ledger mode Ecto

- **Entry.** S6.
- **Deliverables.** `example_code` with `EXAMPLE_LEDGER=ecto` as its default: fact fields declared through the macro on Assignment, OfficeRole, Marking, list membership, employment, and nationality, the genesis migration, the events migration, the history scenarios executed, `priv/schema/code.sql` and `statement/` regenerated. Mode none stays as the second run.
- **Gate.** In `apps/example_code`, the whole CI job of `docs/testing.md` §7:

```
$ mix turnstile.schema_dump && git diff --exit-code priv/schema/
<nothing>; exit=0
$ EXAMPLE_LEDGER=ecto mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter
<the scenarios>, 0 failures
$ EXAMPLE_LEDGER=ecto mix turnstile.assess && git diff --exit-code statement/statement.md
<nothing>; exit=0
$ EXAMPLE_LEDGER=none TURNSTILE_RESULTS=tmp/results-none.json mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter
<the scenarios>, 0 failures, <n> skipped
$ EXAMPLE_LEDGER=none TURNSTILE_RESULTS=tmp/results-none.json mix turnstile.assess --check
exit=0
```

In the Ecto run no scenario is skipped for `needs_ledger`; a test replays a decision recorded before a revocation and reproduces its verdict; the statement prints the genesis date.

### S8a. `turnstile_postgres`

- **Entry.** S7.
- **Deliverables.** `apps/turnstile_postgres`: session settings through `set_config(name, value, true)` inside `around_query/3`, `check` for writes, policy-version events read from `pg_policy` and appended by migrations, the replica-lag component reported "not measured", the declaration, `priv/conformance/` with the RLS migration for the neutral fixture.
- **Gate.** In `apps/turnstile_postgres`:

```
$ mix quality
<green>
$ ls priv/conformance
<the RLS migration>
```

`AdapterCase` for `Turnstile.Postgres` runs as the `turnstile_app` role, and the shape tests count the `set_config` statement as one query.

### S8b. `example_postgres`

- **Entry.** S8a.
- **Deliverables.** `apps/example_postgres`: the binding, `ExamplePostgres.Capabilities`, the migrations written by hand that reassign ownership, enable and force RLS, add the policies and the C7 write gates, `priv/schema/postgres.sql`, the scenario test file, the README with the translation table and the per-rule mechanism table, `statement/`.
- **Gate.** In `apps/example_postgres`, the CI job of `docs/testing.md` §7:

```
$ mix turnstile.schema_dump && git diff --exit-code priv/schema/
<nothing>; exit=0
$ mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter
<the scenarios>, 0 failures
$ mix turnstile.assess && git diff --exit-code statement/statement.md
<nothing>; exit=0
```

One scenario issues a C7-violating write through the owner-role SQL path, not the port, and asserts the database refuses it.

### S9a. `turnstile_cerbos`

- **Entry.** S8b.
- **Deliverables.** `apps/turnstile_cerbos`: attribute declarations, the query plan to `dynamic` with the `filter` fallback recorded as `limited`, policy versions from the policy repository's commit, decision-log reconciliation, the `policy_propagation` latency component, the declaration, `priv/conformance/` with the policies for the neutral fixture.
- **Gate.** In `apps/turnstile_cerbos`:

```
$ mix quality
<green>
$ ls priv/conformance
<the policy files>
```

`AdapterCase` runs under the shared sidecar; one test starts its own sidecar, publishes a version, and asserts one policy-version event; one injects a mismatched decision-log line and asserts a drift finding.

### S9b. `example_cerbos`

- **Entry.** S9a.
- **Deliverables.** `apps/example_cerbos`: the binding, `ExampleCerbos.Capabilities` with C3 as `limited` and its note, the policy files, an empty migration beyond the helpers with a comment saying why, `priv/schema/cerbos.sql`, the scenario test file, the README, `statement/`.
- **Gate.** The same three commands as S8b in `apps/example_cerbos`, with `rev-06` measuring `policy_propagation` and the statement printing it.

### S10a. The OpenFGA client and its fake

- **Entry.** S9b.
- **Deliverables.** In `apps/turnstile_fga`: `Turnstile.Fga.Client` as a behaviour over the calls the adapter and the projector use, `Turnstile.Fga.Client.Fake` on an `Agent` returning values of the real type, `Turnstile.Fga.Projector` with checkpoint per acknowledged write and drain by diff, `rebuild/1` into a fresh store, `drain_once/1`, the checkpoint migration helper, the tuple mapping behaviour; the projector's unit tests against the fake: re-drain convergence, drift between the fold and `Read`, the read-diff-write for a decontrol change, duplicate and missing writes rejected atomically. The frozen interface of S10 is the client behaviour.
- **Gate.** In `apps/turnstile_fga`:

```
$ mix quality
<green>
$ mix test --exclude committed
<the projector and mapping tests against the fake>, 0 failures
```

No test in this stage starts a server.

### S10b. `turnstile_fga`: the adapter

- **Entry.** S10a.
- **Deliverables.** `Check`, `BatchCheck`, `ListObjects` with `caps[:batch_ids]` and the `filter` fallback, `Expand`, consistency per operation, model publication as a policy version, the `projector_drain` latency component, the declaration, `priv/conformance/` with the model and a tuple mapping for the neutral fixture, the three projection cases on the committed repo driving `drain_once/1` against `openfga run --datastore-engine memory`.
- **Gate.** In `apps/turnstile_fga`:

```
$ mix quality
<green>
$ mix test --only committed
<the projection cases: measured lag, a tuple deleted through the client caught by reconcile, re-drain after a simulated crash>, 0 failures
```

`scope` above the cap records `limited` and matches `filter`; the statement fragment prints two inventory items and the drain interval.

### S10c. `example_fga`

- **Entry.** S10b.
- **Deliverables.** `apps/example_fga`: the binding, `ExampleFga.Capabilities`, `priv/fga/model.fga`, the tuple mapping module for the CUI domain, the checkpoint migration, the projector started in `Application.start/2`, `priv/schema/fga.sql`, the scenario test file with a store per test, the README with the translation table, `statement/`.
- **Gate.** The same three commands as S8b in `apps/example_fga`; every sandboxed scenario that writes a fact calls `Turnstile.Test.settle/0` before its check, and `rev-01` prints `projector_drain`.

### S11. Point-in-time review, drift, and replay for four adapters

- **Entry.** S10c.
- **Deliverables.** `mix turnstile.review --at <date>` in `turnstile_assess`; drift scenarios per adapter; replay per adapter: code by commit, Postgres in a scratch database, Cerbos with a throwaway sidecar, OpenFGA with a throwaway in-memory server; `rvw-04` on the owner-role repo's connection.
- **Gate.** In each of the four thin apps, the three commands of S8b pass, and the executed count in `results.json` has grown by the review, drift, and replay scenarios. Then, in `apps/example_code`:

```
$ mix turnstile.review --at <a date after a revocation in the fixture>
<the subject absent>
$ mix turnstile.review --at <the moment before>
<the subject present>
```

For each adapter a replay test reproduces a stored decision's verdict and policy version.

### S12. The README, the statement bodies, and the workflow

- **Entry.** S11.
- **Deliverables.** `README.md`: purpose in one paragraph, the four statement bodies included by reference from `apps/example_<adapter>/statement/statement.md`, a quickstart that runs, links. `docs/glossary-index.md` complete. `.github/workflows/ci.yml` with the `quality`, four thin-app, and `sources` jobs of `docs/testing.md` §7. Every document passes the prose gate.
- **Gate.** At the root, every step of every job in the workflow file run by hand in the order the file gives, each green; then:

```
$ git diff --exit-code README.md apps/*/statement/statement.md apps/*/priv/schema/
<nothing>; exit=0
```

Then the prose gate of `CLAUDE.md`, run over `README.md`, `PLAN.md`, `docs/`, and every app's README, with the line in `docs/writing.md` that lists the banned words excluded, prints `exit=1`.

If `origin` has been pushed to by then, the workflow is green on `main`; if not, the commit message says the jobs ran locally and the workflow is unproven remotely.

## 4. Order

```
S0, S1, S2a, S2b, S2c, S4, S3, S6, S7, S8a, S8b, S9a, S9b, S10a, S10b, S10c, S11, S12
```

Every stage's entry is the one before it. S4 precedes S3 because the thin app binds the adapter. No stage runs beside another.

## 5. After S12

The deferred items return one stage each, when their condition holds: the OSCAL component definition, the 20x KSI output, `--diff` between two dated statements, the event-store ledger mode, and the adoption guide as educational material. None of them changes a frozen interface from S1.
