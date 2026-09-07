# Turnstile delivery plan: stages, sharding, and the example's encoding
*Mode: How-to. Produced 2026-09-07 by a planning agent. A staged workflow for building plan v8, written so each stage is one agent session with a mechanical gate. Every claim cites the plan or the tree. Nothing here changes a decision the plan makes, except where §3 recommends an answer to ⟨open 3⟩. Paths are relative to the repo root; plan files are under `new-plan/`.*

## What the plan starts from

Three facts about the tree shape the stages more than anything in the plan does.

1. **The existing core is the old port, not v8's.** `docs/status.md` calls it "a working core port" (`docs/status.md:30`), but its behaviour is `Turnstile.Provider` with `authorize/4`, `scope/4`, `record/2`, `erase/2`, `with_actor/2` (`apps/turnstile_core/lib/turnstile/port/provider.ex:41-67`). Plan v8's port is `authorize`, `check`, `batch`, `scope`, `explain` with derived `filter` and `review` (`PLAN.md:33`), speaks 800-162's words (`PLAN.md:25`), and reserves *adapter* over *provider* (`PLAN.md:27`). The existing example domain (Org, Project, Label, Compartment: `apps/turnstile_example/README.md:13-22`) is not the CUI domain (`PLAN.md:103-112`), and the package names differ (`turnstile_rbac`, `turnstile_rebac`, `turnstile_openfga` today; `turnstile_code`, `turnstile_ledger`, `turnstile_assess`, `turnstile_fga` in `PLAN.md:156-169`). What carries over is the umbrella scaffolding (`umbrella.exs`), the boundary and Credo wiring, and the *ideas* of `Conformance.Case`, the scenario reader, `LanguageLint`, and `Matrix`. Phase 1 of v8 is a rebuild that reuses a quarry, not an increment. Question 1 in §4 asks the owner to confirm.

2. **No Nix exists yet.** The plan requires a flake as the only path (`PLAN.md:172`, `TESTING.md:17`); the tree has `.tool-versions` and `docker-compose.yml`, CI uses `erlef/setup-beam` (`.github/workflows/ci.yml:16-18`), and `nix` is not on this machine's PATH. Stage 0 is real work, not a formality.

3. **The example already has a compile-time overlay mechanism.** `TURNSTILE_PROVIDER` selects an `elixirc_paths` directory `providers/<p>/` and a second migrations path `priv/repo/providers/<p>/` (`apps/turnstile_example/mix.exs:14-38`; `config/config.exs:6-18`). This is option (c) of §3, already built once, and v8 keeps compile-time binding (`PLAN.md:172`; `CODE.md:57`).

---

## 1. Stages

Thirteen stages, S0 to S12, derived from the seven phases (`PLAN.md:176-184`) and split so one agent session can finish and prove each. Every gate runs from a clean clone as `nix develop -c <command>`; "green" means exit 0 with `warnings_as_errors` (`CODE.md:66-67`).

### S0. Toolchain: the flake and the ephemeral cluster

- **Entry.** None. Can run beside S1.
- **Deliverables.** `flake.nix`, `flake.lock`, `.envrc` at the root (`PLAN.md:152`); the shell provides `beam.packages.erlang_28.elixir_1_20`, `postgresql`, `cerbos`, `openfga` as binaries (`TESTING.md:12-13`); `services-flake` target `nix run .#services` (`TESTING.md:14`); `Turnstile.Test.Cluster.start!/0` in core's test support doing the five steps of `TESTING.md:21-27` (initdb into `tmp/pg-<random>/`, unix socket, two roles, two databases, three repos configured, `at_exit` teardown); `Turnstile.Test.Cerbos.start_shared!/0` and the OpenFGA equivalent (`TESTING.md:45`, `:71`); `.github/workflows/ci.yml` rewritten to install Nix and run `nix develop --command mix quality` with `--partitions 4` (`TESTING.md:79-81`); `.tool-versions` and `docker-compose.yml` deleted (`TESTING.md:17`). Core gains `ecto_sql` and `postgrex` as `only: :test` deps, since core "depends on ecto, not ecto_sql" (`PLAN.md:159`) but Tier 1 runs on Postgres (`PLAN.md:120`).
- **Gate.** On a clean clone: `nix develop -c mix deps.get && nix develop -c mix test` in `apps/turnstile_core` passes, including one smoke test that runs `SELECT 1` through `Turnstile.TestRepos.Sandboxed` over the socket, asserts `turnstile_app` has `NOBYPASSRLS`, and asserts `tmp/pg-*` is absent after exit. `nix develop -c sh -c 'cerbos --version && openfga version'` prints the versions the inventory items will cite (`TESTING.md:17`). The `quality` job is green on a pull request. `git ls-files .tool-versions docker-compose.yml` prints nothing.

### S1. Contracts: the port, events, behaviours, declaration schema, glossaries

- **Entry.** Question 1 and question 3 in §4 answered (keep or quarry; names).
- **Deliverables.** In `apps/turnstile_core`: `Turnstile.Adapter` behaviour with the five calls and `explain` optional (`PLAN.md:33`); the structs that cross it — `Subject`, `Object`, `Decision` with `head_position` and `applied_position` (`PLAN.md:39`; `OPENFGA.md:167`), `Reason`, `FactEvent` with its four kinds (`PLAN.md:45`), `PolicyVersion` (`REFERENCE §5`); `Turnstile.Clock` behaviour (`TESTING.md:53`); `Turnstile.Ledger` and `Turnstile.Projection` behaviours with `rebuild/1` and checkpoint (`PLAN.md:51-53`; `OPENFGA.md:169`); `Turnstile.Declaration` — capability per scenario, origination profile, parameters, inventory item, latency, `requires_ledger` (`REFERENCE.md:67`; `OPENFGA.md:168`); `%Turnstile.Config{}` as a `NimbleOptions` schema (`CODE.md:57`); the scenario id list and groups (`REFERENCE.md:8-19`) as the file the lint reads; the `AdapterCase` template's `use` signature (`TESTING.md:73`) as a stub. Old packages `turnstile_rbac`, `turnstile_rebac`, `turnstile_openfga` and the old example removed or renamed per question 1. Glossaries and the first decision records before code (`PLAN.md:178`); `docs/adr/` restored in whatever form question 3 settles, since the old records were deleted (`status.md:130-133`).
- **Gate.** `nix develop -c mix quality` at the root is green with the new packages present and empty of mechanism; a test enumerates `Turnstile.Adapter.behaviour_info(:callbacks)` and `Turnstile.Ledger.behaviour_info(:callbacks)` against a committed list (the freeze); the banned-word grep (`status.md:193-198`) returns only the expected hits; `mix xref graph --format cycles --fail-above 0` passes (`CODE.md:76`).

### S2. Core mechanisms (three shards)

- **Entry.** S0 and S1 merged.
- **Deliverables.**
  - *S2a, the seam.* `use Turnstile.Repo` with the compile-order check, `Turnstile.Repo.Surface` classifying every `Ecto.Repo` function into query, write, raw, plumbing, the `@before_compile` exhaustiveness failure, overrides injected last, audit mode, the fact-recording hook, the `turnstile:` option schema (`REFERENCE.md:87-101`; `CODE.md:53`); `Turnstile.Credo.NoRawSQL` and `UnmediatedRepo` (`REFERENCE.md:101`); the seam's own Tier 1 cases, including the generated sweep (`REFERENCE.md:99`).
  - *S2b, the fake adapter, the in-memory ledger, Tier 1.* `Turnstile.Adapter.Fake` with an `Agent`-per-test rule table (`TESTING.md:56`); `Turnstile.Ledger.Memory`; `AdapterCase` with the property laws (`TESTING.md:73`), the fail-closed and deny-by-default cases (`PLAN.md:35`), the shape tests of `REFERENCE.md:122-128` that do not need the Ecto ledger, and the three projection cases gated on `declares a projection` (`PLAN.md:120`).
  - *S2c, the generator skeleton.* `apps/turnstile_assess`: `priv/sources.exs` with the three pinned files (`REFERENCE.md:172`), the citation lint, `mix turnstile.assess` printing every control unknown (`PLAN.md:178`), the Rev 5 markdown profile only, `mix turnstile.review` and `--diff` as stubs that print "not available".
- **Gate.** `nix develop -c mix test` in `apps/turnstile_core` passes with `Turnstile.Adapter.Fake` under `AdapterCase`; a test compiles a Repo module with one extra public function and asserts `CompileError` naming it; `nix develop -c mix turnstile.assess` in `apps/turnstile_assess` exits 0 and prints a statement in which every baseline control is "unknown"; the lint rejects a scenario citing `AC-99`. Coverage threshold 90 (`CODE.md:72`).

### S3. The example at v0: a Phoenix app with no Turnstile

- **Entry.** S0 and S1 (needs the scenario ids and, for the schema, question 4 on portions). Runs beside S2.
- **Deliverables.** `apps/turnstile_example` as the CUI domain (`PLAN.md:103-112`): migrations, schemas, contexts, a JWT plug that reads one role (`PLAN.md:128`), fixtures, the hash-chained audit store as a stub module (`PLAN.md:71`), and Tier 2 files whose test names are the scenario sentences (`PLAN.md:118`; `CODE.md:109`) — every scenario present and skipped, so the id list is frozen in code. No `turnstile_core` dependency. Tag `v0-jwt-single-role` (`PLAN.md:146`) once merged.
- **Gate.** `nix develop -c mix test` in the example passes (domain and controller tests only; Tier 2 all skipped with a reason tag); `mix sobelow --config --exit` passes (`CODE.md:80`); a lint in `turnstile_assess` reads the example's test files and asserts the scenario ids equal the frozen list from S1; `grep -r turnstile apps/turnstile_example/mix.exs` prints nothing.

### S4. Rules in code: `turnstile_code` through Tier 1

- **Entry.** S2 merged.
- **Deliverables.** Declared roles and permissions as data, attribute predicates (`PLAN.md:77`; `REFERENCE.md:71`), a policy-version event at boot when the ledger head names an older version (`REFERENCE.md:80`), the declaration, `explain` naming the clause (`REFERENCE.md:62`).
- **Gate.** `nix develop -c mix test` in `apps/turnstile_code` passes `use Turnstile.Conformance.AdapterCase, adapter: Turnstile.Code`; `mix turnstile.assess` with only this declaration prints a statement with no example work (`PLAN.md:120`, "any adapter that passes earns a statement").

### S5. Adoption steps 0 to 8 on the example

- **Entry.** S3, S4, S2c merged; question 2 (encoding) answered, because it decides how step artifacts are committed.
- **Deliverables.** The example walked through the table at `PLAN.md:130-140`: step 0 (core added, seam in audit mode, the unmediated-call inventory committed), 1 (identity-only token, per-request subject), 2 (one check through the port), 3 (enforce; exemption list empty or justified), 4 (role table with privileged and non-privileged roles on separate accounts), 5 (`scope` through the seam), 6 (audited override), 7 (re-authentication), 8 (`mix turnstile.review`). The reference audit store made real (`PLAN.md:179`). The Tier 2 groups each step earns un-skipped (`REFERENCE.md:8-19`). A statement per step committed in the form §3 recommends.
- **Gate.** Per step: `nix develop -c mix test` in the example passes with that step's Tier 2 groups un-skipped and the rest still skipped; `mix turnstile.assess --diff <previous step>` prints only the controls the table says the step earns (`PLAN.md:130-140`, "Earns" column) and nothing turning red; at step 3 the audit-mode inventory is empty; at step 8 the first real statement with ledger mode none (`PLAN.md:179`). Final: all Tier 2 scenarios that do not need history pass; scenarios needing history (AC-2(4), point-in-time) remain skipped with reason `:needs_ledger`.

### S6. The Ecto ledger (two shards)

- **Entry.** S2 merged. Runs beside S4 and S5.
- **Deliverables.** *S6a:* the table and migration helper, append-only grant, genesis, `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, `bulk_insert/3` with the null-safe difference condition, `Dialect.Postgres` and `Dialect.Generic` (`REFERENCE.md:132-139`, `:156-168`). *S6b:* the visibility-safe reader, reconcile and drift, replay as fold-plus-policy-version, the ledger conformance case (`REFERENCE.md:144`, `:154`; `PLAN.md:51`). The seam's fact hook (S2a) is the shared interface; both shards consume it and neither changes it.
- **Gate.** `nix develop -c mix test` in `apps/turnstile_ledger` passes: the ledger conformance case; the shape tests at `REFERENCE.md:123-127` with exact counts; the `@tag :committed` interleaved-transactions case (`REFERENCE.md:144`; `TESTING.md:65`); the atomicity case; `@tag :tripwire` under ten seconds (`REFERENCE.md:128`).

### S7. The example at v9: history

- **Entry.** S5 and S6 merged.
- **Deliverables.** `turnstile_ledger` in the example; fact fields declared on Assignment, OfficeRole, Marking, list membership, employment, nationality (`REFERENCE.md:53`, C11); genesis migration; the AC-2(4) and point-in-time scenarios un-skipped; the step-9 statement.
- **Gate.** Tier 2 passes with ledger mode `ecto`; `mix turnstile.assess --diff <step 8>` shows AC-2(4) and AU-9 turning and the genesis date printed (`REFERENCE.md:154`); a test replays a decision recorded before a revocation and reproduces its verdict (`PLAN.md:51`).

### S8. Postgres row-level security and v10a

- **Entry.** S7 merged (policy versions are appended by the migration as facts: `REFERENCE.md:81`).
- **Deliverables.** `apps/turnstile_postgres`: session settings by `SET LOCAL`, policy-version events read from `pg_policy`, replica-lag measurement, the declaration (`REFERENCE.md:69`); in the example, the `postgres` overlay: the migration that reassigns ownership, enables and forces RLS, adds policies and the write gates for C7 (`REFERENCE.md:56`), and the committed `pg_dump` (§3).
- **Gate.** Tier 1 for `Turnstile.Postgres`; Tier 2 for the example built with the postgres adapter; a Tier 2 case where a C7-violating write issued through the owner-side SQL path, not the port, is refused by the database (`REFERENCE.md:56`, "whether or not the application asked"); the schema dump diff is clean.

### S9. Cerbos and v10b

- **Entry.** S7 merged. Runs beside S8 and S10.
- **Deliverables.** `apps/turnstile_cerbos`: attribute declarations, query plan to `dynamic`, policy versions from the policy repository's commit, decision-log reconciliation (`PLAN.md:79`; `REFERENCE.md:70`); the example's `cerbos` overlay: policy files, the materialized effective-controls column or the `filter` fallback for C3 (`REFERENCE.md:56`), an empty migration with the note saying why.
- **Gate.** Tier 1 for `Turnstile.Cerbos` under the shared sidecar (`TESTING.md:45`); Tier 2 with `limited` recorded where the plan says (`REFERENCE.md:56`); a test that starts its own sidecar, publishes a version, and asserts one policy-version event; a reconciliation test that injects a mismatched sidecar log line and asserts a drift finding.

### S10. OpenFGA and v10c (three shards)

- **Entry.** S6 and S7 merged (the adapter requires a ledger: `OPENFGA.md:143`).
- **Deliverables.** *S10a, projector:* `Turnstile.Fga.Projector` with checkpoint, batching, read-before-write or tolerated errors, `rebuild/1`, reconcile via `Read`, against an in-memory fake client first (`OPENFGA.md:137-141`), plus the three projection cases in Tier 1 (`REFERENCE.md:180`). *S10b, adapter:* `Check`, `BatchCheck`, `ListObjects` with the cap and `filter` fallback, `Expand`, consistency per operation, model publication as a policy version (`OPENFGA.md:147-151`). *S10c, example overlay:* `priv/fga/model.fga` as written at `OPENFGA.md:29-109`, `Example.Authz.FgaMapping` per the table at `OPENFGA.md:117-133`, the checkpoint migration, configuration (`OPENFGA.md:158`).
- **Gate.** Tier 1 for `Turnstile.Fga` including measured lag, out-of-band tuple delete caught by reconcile, and re-drain convergence (`OPENFGA.md:159`); Tier 2 with a store per test (`TESTING.md:71`); `scope` above the cap records `limited` and matches `filter`; the statement prints two inventory items and the drain interval (`OPENFGA.md:160`).

### S11. Point-in-time review, drift scenarios, `--diff`, replay for four adapters

- **Entry.** S8, S9, S10 merged.
- **Deliverables.** `mix turnstile.review --at <date>` (`PLAN.md:122`); `--diff <ref>` real; drift scenarios per adapter; replay per adapter — code by commit, Postgres in a scratch database, Cerbos with a throwaway sidecar, OpenFGA with a throwaway in-memory server (`REFERENCE.md:69-72`; `OPENFGA.md:151`).
- **Gate.** One Tier 2 scenario per adapter: revoke a fact, then `review --at` the moment before revocation lists the subject and the moment after does not; for each adapter a replay test reproduces a stored decision's verdict and policy version; `mix turnstile.assess --diff v0-jwt-single-role` prints the full progress bar without error.

### S12. Outputs validated, README, adoption guide check

- **Entry.** S11 merged.
- **Deliverables.** OSCAL SSP, POA&M, and CRM validated against FedRAMP's templates; KSI JSON against the 20x docs (`PLAN.md:184`); the README with four statements side by side (`PLAN.md:83`); `docs/how-to/adopt.md` and `docs/how-to/bump-sources.md` (`PLAN.md:153`); the adoption verification job (§3).
- **Gate.** A CI job runs the OSCAL validator and the KSI schema check and is green; the README's four statement sections are generated files that `git diff --exit-code` proves current after `mix turnstile.assess` for each adapter; the adoption verification job is green on `main`.

### Dependencies

```
S0 ─┬─────────────► S2 ─┬─► S4 ─┐
S1 ─┘        │          │       ├─► S5 ─┐
             └─► S3 ────┼───────┘       ├─► S7 ─┬─► S8  ─┐
                        └─► S6 ─────────┘       ├─► S9  ─┼─► S11 ─► S12
                                                └─► S10 ─┘
```

Parallel sets: {S0, S1}; {S2a, S2b, S2c, S3}; {S4, S6a, S6b}; {S5, S6}; {S8, S9, S10a, S10b, S10c}; S11's five shards; S12's three shards. S10a may start after S6, before S7.

---

## 2. Sharding plan

### Interfaces frozen before shards start

Each freeze is a committed file with a test that fails if it changes without the file changing; a shard that needs a change proposes it to the integrator, who lands it on the stage branch first.

| Frozen at | Interface | Where it lives | Consumers |
|---|---|---|---|
| S1 | `Turnstile.Adapter` callbacks and the structs crossing it | `apps/turnstile_core/lib/turnstile/adapter.ex`, a `behaviour_info` snapshot test | every adapter shard, the seam, Tier 1 |
| S1 | `Turnstile.Ledger`, `Turnstile.Projection`, the four `FactEvent` kinds | core | S6, S10a |
| S1 | `Turnstile.Declaration` schema | core; the generator reads it | S2c, every adapter |
| S1 | Scenario ids and groups | `apps/turnstile_assess/priv/scenarios.exs` or the lint's list | S3, S5, adapters' capability declarations |
| S1 | `%Turnstile.Config{}` schema; the `turnstile:` option schema | core | seam, ledger, example |
| S0 | `Turnstile.Test.Cluster.start!/0`, the three repo names (`TESTING.md:26`) | core test support | every `test_helper.exs` |
| S2a | The Repo surface classification and the ecto pin (`REFERENCE.md:89-95`) | core | S6 (bulk API refusal), S8 (session settings inside the seam) |
| S2b | `use Turnstile.Conformance.AdapterCase, adapter:` and `Turnstile.Conformance.Gen` | core | every adapter |
| S3 | The example's schema (v0 migrations) and, at S7, its fact mapping | example `priv/repo/migrations` | S8, S9, S10c overlays |
| S6a | The ledger table shape and the reader's signature | ledger | S6b, S10a |

### Per stage

| Stage | Agents | Split | Why it holds |
|---|---|---|---|
| S0 | 1 | — | The flake, the cluster helper, and CI must agree on one closure; three files, one mind. |
| S1 | 1 | — | **Trap.** The contract stage is where names, struct fields, and callback arities are chosen together; two agents produce two vocabularies. Glossaries first (`PLAN.md:178`). |
| S2 | 3 | S2a `lib/turnstile/repo/**` + `lib/turnstile/credo/**`; S2b `lib/turnstile/conformance/**` + `lib/turnstile/adapter/fake.ex` + `lib/turnstile/ledger/memory.ex`; S2c `apps/turnstile_assess/**` | Directory-disjoint. S2a owns the seam's Tier 1 cases in `test/turnstile/repo/`; S2b owns the port's in `test/turnstile/conformance/`. **Trap inside S2a:** the classification of every Repo function (`REFERENCE.md:89-93`) is one list one person holds; do not split the seam. |
| S3 | 1, or 2 by context | Contexts by aggregate: Accounts+Agencies+Offices+Programs; Documents+Markings+Categories | If two: each owns its migration files, schemas, contexts, fixtures, and scenario files under `test/scenarios/<group>_test.exs`; the shared `Example.Repo`, router, and JWT plug belong to the first. The integrator cuts `v0`. |
| S4 | 1 | — | One package, small. |
| S5 | 1 per step, serial | Steps are ordered by construction ("every step ships alone", `PLAN.md:128`) | **Trap.** Steps 0 to 3 are one mind: the audit-mode inventory (`PLAN.md:132`) is a whole-application classification into decision or exemption (`PLAN.md:65`), and the empty list at step 3 is the proof. One agent for 0–3 in one session. Steps 4–8 may each be a fresh session, handing off through the step's committed statement. |
| S6 | 2 | S6a `lib/turnstile/ledger/{table,genesis,facts,dialect/**}`; S6b `lib/turnstile/ledger/{reader,reconcile,replay}` + the conformance case | S6b stubs the reader over a plain `ORDER BY position` until S6a's dialect lands, then swaps; the `:committed` interleaving test belongs to S6b. |
| S7 | 1 | — | Declaring fact fields is a domain-wide judgement ("a bookkeeping column is not one", `PLAN.md:45`). |
| S8 | 2, serial | Adapter package then example overlay | The overlay agent needs the adapter's session-setting names; hand off through Tier 1 green. |
| S9 | 2, serial or parallel | Package; overlay (policies live in the example: `TESTING.md:45`) | Parallel is possible if the policy file layout is agreed first; serial is safer. |
| S10 | 3 | S10a `lib/turnstile/fga/projector/**` against a fake client; S10b `lib/turnstile/fga/{adapter,client}.ex`; S10c example `adapters/fga/**`, `priv/fga/` | **Trap:** the model and the tuple mapping are one design (`OPENFGA.md:27`, `:115`) and belong to one agent (S10c); the projector's mechanics (checkpoint, batching, convergence) are adapter-independent and shard cleanly. S10a and S10b meet at the client behaviour, frozen first. |
| S11 | 5 | One per adapter replay (in that adapter's package) + one for review/diff in `turnstile_assess` | The assess shard defines the review output shape first; adapter shards implement `replay/2` against it. |
| S12 | 3 | OSCAL validation; KSI validation; README + adoption how-to + CI job | Disjoint files. |

### Worktree and branch discipline

The repo's habits are one commit per idea, sign-off via `git -c commit.gpgsign=false commit -F -`, and worktrees fast-forwarded and removed (`status.md:202-204`); `.claude/worktrees/` is ignored (`.gitignore:15`).

- **Stage branch.** `stage/NN-<name>` from `main`. The integrator (the parent agent or the owner) owns it.
- **Shard branch.** `stage/NN-<name>/<shard>` from the stage branch, in a worktree at `.claude/worktrees/stage-NN-<shard>`. A shard touches only the paths in its row above; a change outside them is a request to the integrator, not a commit.
- **Landing a shard.** The shard rebases onto the stage branch, runs the stage's gate command, and the integrator fast-forwards the stage branch (`git merge --ff-only`). No merge commits: the plan's tags-and-diffs design and the owner's linear history both assume one line.
- **Landing a stage.** The integrator runs the gate on the stage branch from a clean clone (the gates above say "clean clone" for this reason), then fast-forwards `main`, removes every worktree (`git worktree remove`, `git branch -d`), and cuts any tag the stage defines.
- **One commit per idea inside a shard.** A shard that arrives as one squashed commit is rejected; the integrator reads the commits as the review.
- **Frozen files are guarded.** A pre-merge check on the stage branch: `git diff --name-only main... | grep -E '<frozen paths>'` is empty for a shard branch, non-empty only on the integrator's own commits.

---

## 3. Encoding the per-adapter example

The plan's current choice: a linear history from `v0-jwt-single-role` through `v9`, then `v10a`, `v10b`, `v10c`, each tag with its statement committed beside it and a CI job that checks out every tag and regenerates (`PLAN.md:146`; `TESTING.md:82` — which still says `v0`…`v10b` and omits `v10c`; a doc fix). Open 3 defers the decision to the end of Phase 2 (`PLAN.md:216`). The owner asks whether patch files would be better.

A correction first: under plan v8 the OpenFGA overlay does **not** drop fact tables. The engine's store "is a copy" fed by a projector that drains the ledger (`OPENFGA.md:23`), and the example's schema change is "a checkpoint migration" (`OPENFGA.md:158`). Dropping fact tables was the old plan (root `PLAN.md:67-69`). The four schema diffs are therefore: code, empty; Postgres, ownership, RLS, policies, functions (`REFERENCE.md:69`); Cerbos, empty with a note; OpenFGA, one checkpoint table. All four are still part of the artifact, and the Postgres one is the teaching artifact.

Two facts about this repo shape every option:

- **The umbrella couples the example to the library.** A tag of the example is a tag of `turnstile_core` and `turnstile_assess` at that moment. The generator "exists from day one" and grows through S12 (`PLAN.md:178`, `:184`), so its output format changes many times during Phases 2 to 7. Any committed statement is a function of (example code, generator version).
- **The statement is a fold over inputs the plan already names:** "declarations, results, configuration, and the pinned sources" (`PLAN.md:122`). Those inputs are data; the statement is a rendering.

### a. Tags on a linear history plus three branch tips (the plan's choice)

*CI.* For each of twelve refs: check out into a worktree, `nix develop` at that ref (its own `flake.lock`; at least three distinct closures because `v10b` adds Cerbos and `v10c` adds OpenFGA to the shell), `mix deps.get`, compile the whole umbrella, start an ephemeral cluster and the sidecars, run Tier 2 to produce results, run the generator, diff. Twelve umbrella compiles and twelve Tier 2 runs per pull request, or a nightly job that lets the guide rot for a day.

*Propagating a fix to v3.* `v4`…`v9` sit after `v3` on `main`, interleaved with library commits (S6 lands between S5 and S7). Fixing `v3` means `git rebase --onto` for everything after it, resolving conflicts at each step, re-running the generator at each, force-moving nine tags and three branch tips, and rewriting `main` — which the fast-forward-only habit forbids (`status.md:204`). The alternative, fix forward and leave `v3` wrong, means the guide teaches the bug.

*Generator changes.* Every change to `turnstile_assess`'s output invalidates every committed statement, because the statement at `v3` was rendered by the generator at `v3`. Re-rendering with the current generator is impossible without rebase, since the current generator does not compile against `v3`'s core. This is the decisive cost: it is not a Phase 2 cost at all, it is a cost paid on every generator commit through Phase 7.

*Agent shard.* A shard for step 5 checks out `v4`, works, tags `v5`. Fine while steps are serial; impossible to run two steps in parallel; and any core fix a step needs lands *before* the tag, forcing the library to be developed in lockstep with the example's history.

*Reader.* `git checkout v5` and read; the diff between steps is `git diff v4 v5`. Good, when the tags are right.

*Rot.* Silently, with every generator change, unless the per-PR job runs, in which case loudly and expensively.

### b. Patch files applied in sequence

`apps/turnstile_example/adoption/NN-<step>.patch`, `mix turnstile.adoption.apply N` applying `01..NN` onto the base in a temp worktree; CI applies all, compiles, regenerates.

*Rot.* Every change to the base app's context lines breaks a patch; `Styler` and the formatter (`CODE.md:73`) rewrite idioms across files and break many. A refactor of the seam's option name touches every step's patch.

*Review.* A pull request changes a `.patch` file; the reviewer reads a diff of a diff. Credo, the type checker, and the banned-word lint see none of the patched code until CI applies it.

*Editing step 5 when 7 exists.* Regenerate 5, then re-apply 6 and 7 by hand or by `git am` with conflict resolution — the rebase cascade of (a) with worse tooling and no history.

*Agent shard.* A shard produces a `.patch`, which it can only test by applying in a scratch worktree; two shards editing adjacent steps conflict on context lines.

*Reader.* Better than nothing: the step is a readable diff. Worse than (a): the reader cannot open the app at step 5 in an editor without applying.

Verdict: dominated by (a) on every axis except "one checkout has everything". Rejected.

### c. One source tree with compile-time overlays and a step number

Base app plus `apps/turnstile_example/adapters/<a>/` compiled by `elixirc_paths` and `priv/repo/adapters/<a>/` as the second migrations path — what the tree already does (`apps/turnstile_example/mix.exs:22-38`). Adapter bound via `Application.compile_env/3` (`CODE.md:57`). CI: a four-way matrix, each with its own `MIX_BUILD_ROOT` (as the old CI header intended, `.github/workflows/ci.yml:5-7`), each running Tier 2, `mix turnstile.assess`, `pg_dump --schema-only` diffed against `priv/schema/<a>.sql` (the old plan's mechanism, root `PLAN.md:150-152`).

*Adapters.* This is the right shape for `v10a/b/c`. The README's four statements are four CI artifacts from one tree (`PLAN.md:83`). The schema diff is generated, not remembered. A core change recompiles all four on every pull request, so nothing rots. Shards are directory-disjoint. A reader opens `adapters/postgres/` and `priv/repo/adapters/postgres/` and sees exactly what "migrating to Postgres" means.

*Adoption steps.* A `config :turnstile_example, adoption_step: n` with feature flags is where (c) fails. Step 1 replaces the JWT plug (`PLAN.md:133`); step 3 flips the seam from audit to enforce (`PLAN.md:135`); step 9 adds a dependency. An app that contains every step behind flags is not an app an adopter recognizes, and the example "is the thing an assessor reads first" (`CODE.md:80`). The progress bar can be produced by flags, but it would be a bar over a program nobody ships. Rejected for steps; adopted for adapters.

### d. Separate app directories per step or adapter

`apps/example_v0`, `apps/example_v1`, … eleven Phoenix apps in the umbrella, or four per-adapter apps with a shared library app. Duplication: eleven copies of the domain, or a shared library that hides the very changes the steps are meant to show; a schema fix is eleven migrations. Umbrella compile time multiplies. The one place it earns its cost is a single "before" fixture — the plan's own alternative in open 3 (`PLAN.md:216`) — and even that is a tag under the recommendation below. Rejected.

### e. Hybrid: overlays for adapters, immutable step tags on main, statements rendered from committed evidence

- **Adapters** as in (c). Four overlays, four CI builds, four dumps, four statements.
- **Adoption steps** as commits on `main`, in order, built by walking the path (`PLAN.md:146` still holds). Each step's last commit carries a lightweight tag `adopt/0`…`adopt/9` that is **never moved**. Fixes go forward; if a step was wrong, the how-to says so and links the fix, which is how "dated evidence" is meant to behave (`PLAN.md:19`, "the same artifact, dated").
- **Per-step evidence, not per-step statements, is what CI guards on every pull request.** At each step the agent commits the generator's *inputs* — the declaration, the Tier 2 results, the configuration, the seam surface — as `apps/turnstile_example/adoption/steps/NN/evidence.json` with the commit hash and date in its header, and the rendered statement beside it. Because the statement is a fold over those inputs (`PLAN.md:122`), the current generator can re-render all ten statements from committed evidence on every pull request with no checkout: `mix turnstile.assess --from adoption/steps/NN/evidence.json` diffed against `NN/statement.md`. When the generator's format changes, the ten statements are regenerated in the same commit, the way the pinned-source bump commits the lint's diff (`REFERENCE.md:174`). The progress bar is `--diff` over consecutive evidence files.
- **The evidence itself is guarded nightly.** A job checks out each `adopt/N` in a worktree, builds it with the toolchain of that commit, runs Tier 2, and asserts the produced evidence equals the committed evidence. This is (a)'s job, moved off the pull-request path and made cheap to interpret: a failure means the tagged code no longer produces what it produced, which after an immutable tag can only mean an environmental drift (the flake, the sidecar versions) worth knowing about.
- **`v0` is `adopt/0`**, not a fixture app; the nightly job compiles it. If the owner wants the all-red statement runnable on every pull request, it comes from `adoption/steps/00/evidence.json`, which is all-unknown.

*Agent shard.* Steps are serial sessions on `main` (S5); adapters are parallel shards by directory (S8–S10). No rebase cascade exists because nothing behind a tag is edited.

*CI.* Per pull request: four adapter builds plus ten cheap re-renders. Nightly: ten checkouts.

*Reader.* `git log --oneline adopt/4..adopt/5 -- apps/turnstile_example` is step 5; `git diff adopt/4 adopt/5` is its diff; `adoption/steps/05/statement.md` is what it earned; `adapters/postgres/` plus `priv/schema/postgres.sql` is what Postgres costs. `docs/how-to/adopt.md` is the annotated list of those commands.

*Rot.* Statements rot with the generator and are re-rendered in the same commit, guarded per pull request. Evidence rots only with the environment, guarded nightly. Overlays cannot rot; they compile on every pull request.

### Recommendation

Adopt (e). The reason is the umbrella: a tag freezes the library along with the example, so under (a) every generator change through Phase 7 either invalidates twelve statements or forces a rebase cascade that rewrites `main` against the repo's fast-forward habit, while under (e) the statement is treated as what the plan says it is — a rendering of committed evidence — and only the evidence is tied to a commit. Overlays keep the plan's own compile-time binding and "built once per adapter" (`PLAN.md:83`, `:172`) and make the four schema diffs generated artifacts rather than remembered ones. The plan's decision line, "built by migration, tags as the guide, a CI diff as the guard" (`PLAN.md:207`), survives with one word changed: the diff is on evidence and on adapter builds, and the tags are markers rather than checkouts. Decide it now rather than at the end of Phase 2, because S3 and S5 need to know where the evidence file lives.

---

## 4. Questions the owner must answer before sharding begins

1. **Keep the existing core or quarry it?** The existing port, example, and provider packages are the old plan's. *Default:* quarry. S1 deletes `apps/turnstile_rbac`, `turnstile_rebac`, `turnstile_openfga`, and the old example; keeps `umbrella.exs`, `.credo.exs`, and the boundary wiring; reuses the conformance `Case`, scenario reader, and `LanguageLint` under new names. If "keep", S1 becomes a rename-and-extend stage twice its size and S3 is a domain rewrite inside a live app.
2. **The encoding, open 3, now.** *Default:* (e) above. Changes S3 (evidence file location), S5 (tags never move), S8–S10 (overlay directories), S12 (the nightly job).
3. **Names, open 2 (`PLAN.md:215`), before S1.** The library name, `mix turnstile.assess`, `Turnstile.Adapter`, and `turnstile_code` over the existing `turnstile_rbac`. *Default:* as `PLAN.md:150-170` spells them. S1 freezes them; renaming later touches every shard.
4. **Portion marking, open 1 (`PLAN.md:214`), before S3.** It is in the example's schema, C4, the FGA model (`OPENFGA.md:111`), and every adapter's capability list. *Default:* document-level only through S12; C4 declared unsupported with a POA&M row per adapter; `Portion` absent from v0's migrations so the frozen schema does not carry a table nothing reads.
5. **Where CI runs Nix.** GitHub-hosted runners with a Nix installer and a binary cache, or a self-hosted runner with a warm store. This sets S0's gate and the cost of the four-way adapter matrix and the nightly checkouts. *Default:* GitHub-hosted with a cache action; revisit if the matrix exceeds twenty minutes.
6. **If `cerbos` or `openfga` is not in the locked nixpkgs (⟨verify⟩ at `TESTING.md:13`), package from source or fetch release binaries?** Packaging from source is a stage of its own. *Default:* fetch the pinned release binaries in the flake with a hash, cite the release URL the way `.tool-versions` cites builds today (`.tool-versions:1-3`), and file source packaging as later work.
7. **Postgres major.** `TESTING.md:13` says 17 ⟨choose⟩; the tree pinned 18.6 (`docker-compose.yml:9`). RLS behaviour and `pg_dump` output differ across majors, and the dump is a committed artifact under (e). *Default:* the newest major the locked nixpkgs ships; record it in S0's commit message and the inventory item.
