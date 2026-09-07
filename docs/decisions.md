# Decisions for plan v9
*Mode: Reference. The decision log the v9 plan and its companions are written from. Sources: `plan/review/owner-answers.md` (owner decisions, final), `plan/review/holes.md` (28 ranked holes in v8), `plan/review/repo-lessons.md` (what the first attempt learned), `plan/review/toolchain-pins.md` (verified versions), `plan/review/delivery-plan.md` (stages and frozen interfaces). Section names cited as PLAN §, REFERENCE §, TESTING §, CODE § refer to the v8 files under `plan/v8/`; the v9 files that replace them are named in D43. Written 2026-09-07.*

## Owner decisions

### D1. Repo reset on an orphan branch
**Decision.** The v9 work lives on an orphan branch in this repository whose first commit is `plan/` (v8 plus the review). The previous tree is kept under the ref `attempt-1`.
**Because.** owner-answers Q1. The old tree's vocabulary (provider, actor, vocabulary, atom reasons), package list, environment, and example domain all change; repo-lessons §E found nothing an in-place rewrite would preserve that `git show attempt-1:<path>` does not.
**Consequences for v9.** PLAN.md: no migration-from-the-old-tree paragraph; holes #27 is moot. Reusable files are ported by `git show attempt-1:<path>` (D40, D43). `attempt-1` is currently a branch at `0f4888b`, not the tag Q1 names; the S0 agent creates the tag at that commit and removes the branch, so one ref carries the name.

### D2. The example is a library app plus four thin apps
**Decision.** `turnstile_example` holds the CUI domain, schemas, contexts, the web layer, and the scenario tests as shared test support. `example_code`, `example_postgres`, `example_cerbos`, `example_fga` each depend on it and add only the adapter binding, migrations, policies or model, per-rule capability declarations, and config. Each thin app has its own CI job.
**Because.** owner-answers Q2a. One tree per adapter is the shape delivery-plan §3 option (c) already found right for adapters; four thin apps make the four statements four build artifacts that cannot rot.
**Consequences for v9.** PLAN §Packages and conventions and §The example describe the split (D44 has the layout and who owns what). TESTING §7: the `quality` job plus one job per thin app, each running the shared scenarios. REFERENCE §3 notes "runs once per thin app" where v8 says "once per adapter". Delivery stages S3, S5, S8, S9, S10 are recut (D46).

### D3. Adoption steps are dropped
**Decision.** No `v0`…`v10` tags, no per-step statements, no `tags` CI job, no adoption table. One statement per thin app, regenerated on every pull request. The adoption path may return as educational material after implementation.
**Because.** owner-answers Q2b. delivery-plan §3 showed every encoding of the steps either rots with each generator change or forces a rebase cascade.
**Consequences for v9.** PLAN.md: remove §Adoption entirely and the Phase 2 tag work from §Phases; open decision 3 closes. TESTING §6 drops the "committed statement per example tag" sentence and §7 drops the `tags` job. COMPANION §13 is not absorbed except as one sentence in D42. holes #22 is moot. The example is built with the seam enforcing from its first commit; there is no audit-mode walk (audit mode still exists as a library feature, D32).

### D4. Names
**Decision.** "adapter" is the word; `Turnstile.Adapter` is the behaviour. Library packages: `turnstile_core`, `turnstile_ledger`, `turnstile_code`, `turnstile_postgres`, `turnstile_cerbos`, `turnstile_fga`, `turnstile_assess`, `turnstile_example`. Thin apps: `example_code`, `example_postgres`, `example_cerbos`, `example_fga`, the only packages without the prefix. The library is Turnstile; the task is `mix turnstile.assess`.
**Because.** owner-answers Q3.
**Consequences for v9.** PLAN.md open decision 2 closes; §Packages lists the twelve apps as in D44. CODE §4 Naming keeps `Turnstile.` for library modules and adds `Example.` for the library app and `ExampleCode.`, `ExamplePostgres.`, `ExampleCerbos.`, `ExampleFga.` for the thin apps.

### D5. Portion marking is modeled
**Decision.** `Portion(marking: Marking)` under `Document`. A redacted read returns the document with unreadable portions removed. `scope` works at portion level and C13 holds for portions. C4 (banner) stays in the domain. Each adapter filters portions as their own rows with their own policy; for `turnstile_postgres` that is a second RLS policy on the portions table.
**Because.** owner-answers Q4. Portions are what make C3 and C4 exercise each mechanism differently, which is why the domain was chosen.
**Consequences for v9.** PLAN §The example: the schema block loses ⟨open 1⟩; the paragraph gains the redacted read and "C13 holds for portions"; open decision 1 closes. REFERENCE §3: C4 reads "a Document's marking is the union of its Portions' markings, enforced at write time in the domain and tested as a scenario"; the adapter notes gain a portion line each (code: a `read` operation on Portion; Postgres: the second policy; Cerbos: a `portion` resource kind with its own policy; OpenFGA: a `portion` type with a `document` parent, flags on portions, the `from portion` idiom at OPENFGA.md:111). `Portion` is a protected schema with its own object type (D10) and is not a carried relation of Document, so `preload(:portions)` needs its own `scope` decision, which is how the redacted read is built. `Portion.marking` fields are fact fields (D12). Scenario table (D30) gains portion scenarios under enforcement and least privilege. Affects `turnstile_example`, all four thin apps.

### D6. Ledger positions come from a counter row
**Decision.** Every fact-writing transaction locks one row in a library-owned counter table and takes the next positions from it. Positions are commit-ordered with no gaps; the reader is "from position N". The serialization cost is measured and printed in the statement. The same mechanism on every database; the dialect seam stays so a Postgres watermark reader can be added later.
**Because.** owner-answers Q5. holes #2 showed the xmin reader skips events and #13 showed the head stamp made replay inexact; the counter row removes both.
**Consequences for v9.** REFERENCE §9 rewrites: counter table `turnstile_ledger_counter(name, position)` with one row named `default`; take by `SELECT ... FOR UPDATE` (the dialect's lock clause), advance by the number of events, insert events with the positions taken; the head read is a plain select of the row. The phrase "visibility-safe reader" goes away everywhere (PLAN §The ledger, REFERENCE §4 OpenFGA note, §11, TESTING §6, OPENFGA §4). REFERENCE §11 reader-strategy row becomes "counter row; a watermark reader is a later dialect option". PLAN §Decisions replaces "sequence positions with a visibility-safe reader" with "a counter row; commit order is position order". Tier 1 keeps the interleaved-transactions case on the committed repo as the proof that no event is skipped, and adds a measurement of the lock's cost that the generator prints. TESTING §5 positions row: "positions taken inside a rolled-back sandbox transaction are rolled back with it".
Sandbox consequence, an orchestrator call not an owner decision: a sandboxed test holds its transaction for its whole life, so two async tests writing facts would contend on the `default` row. The counter row is therefore named in `%Turnstile.Config{}` (`ledger_counter: "default"`); the test cluster's sandbox setup inserts a per-test row inside the sandbox transaction and points the config override at it, so async fact-writing tests never contend; committed-repo tests use `default`. Affects `turnstile_ledger`, `turnstile_core` test support.

### D7. The adapter is bound at boot; capability declarations live in the thin apps
**Decision.** Core reads the adapter from `%Turnstile.Config{}` at boot; Tier 1 binds per test module and all four adapters run in one `mix test`. Each thin app fixes its adapter in config. `Application.compile_env/3` is reserved for the example's generated per-operation functions. Per-rule capability declarations (native, limited, unsupported per C-rule) live in `example_<adapter>`; adapter packages declare only domain-free facts: requires a ledger, scope cap, inventory item, origination defaults, parameters.
**Because.** owner-answers Q6; closes holes #7 and restores ADR-0031's placement (repo-lessons A7).
**Consequences for v9.** CODE §2 Configuration: "the adapter is a field of `%Turnstile.Config{}`"; delete "bound with `Application.compile_env/3`". PLAN §Packages: delete "the adapter bound at compile time". REFERENCE §4 declaration paragraph splits into the adapter's declaration (domain-free) and the thin app's capability declaration (per C-rule); REFERENCE §13's "C3, C4, C9 native; C8 adapter-side" moves to `example_fga`'s declaration. TESTING §6 unchanged in intent; `AdapterCase` passes the adapter through the config override. Optional callbacks are answered at runtime (D36).

### D8. Toolchain pins
**Decision.** Lock `nixos-unstable`; `beam.packages.erlang_29.elixir_1_20` (OTP 29.0.6, Elixir 1.20.4); `postgresql_18` written explicitly (18.6); `openfga` from nixpkgs (1.19.0); Cerbos v0.55.0 from its release archive through a `fetchurl` derivation with hashes per system (Linux x86_64, Linux arm64, Darwin arm64, Darwin x86_64); services-flake for `nix run .#services`. Nix is not installed on the development Mac; the S0 agent installs it and stops to ask before running the installer. No Docker.
**Because.** owner-answers Q7; toolchain-pins §3, §4, §2, §5, §6 verified on 2026-09-07. Closes holes #23.
**Consequences for v9.** TESTING §2: replace `erlang_28` with `erlang_29`, "17 ⟨choose⟩" with `postgresql_18`, and the ⟨verify nixpkgs⟩ with "openfga from nixpkgs; cerbos fetched, since it is in no nixpkgs branch (toolchain-pins §1)". CODE §3 Elixir row: OTP 29. Every pin cites toolchain-pins with its date, and S0's handoff re-verifies. delivery-plan S0 deliverables gain the Cerbos derivation and the installer stop.

### D9. Scope of the first implementation
**Decision.** The generator emits one Rev 5 markdown statement per thin app: implementation status per control, responsibility split, parameters, evidence (scenarios and results, commit, date, versions, latency and components, ledger mode, seam surface and exemptions, inventory items), and gaps. Deferred and recorded (D42): OSCAL component definition, 20x KSI output, `--diff`, the event-store ledger mode. Kept: all four adapters including OpenFGA and its projector, the ledger in Ecto and none modes, `mix turnstile.review`.
**Because.** owner-answers Q10.
**Consequences for v9.** PLAN §Evidence: the generator paragraph loses the OSCAL, 20x, and `--diff` sentences and gains a pointer to the deferred list; §Words keeps the three pinned sources but the 20x docs are read by the lint only. PLAN §The ledger: two modes, Ecto and none, with a sentence that a third is deferred. PLAN §The line: the second altitude test ("bring your own store") stays as a design constraint but is marked deferred. PLAN §Phases 6 and 7 shrink (D46). REFERENCE §10 drops the event-store row into a note; §12 keeps the 20x docs pin for the lint. TESTING §6: mneme assertions cover POA&M rows, CRM rows, and one control's statement. `turnstile_assess`: markdown profile, `review`, the lint, the formatter (D16).

## Holes that block implementation

### D10. Which decision applies to which query
**Decision.** A schema is protected iff it declares an object type. The seam refuses a query whose root source is a protected schema and whose decision names a different object type. Preload and association queries need their own decision unless the parent schema declares the association as a carried relation; a multi-source query is judged by its root source and every other protected source must be carried by it. Queries on unprotected schemas pass without a decision and the statement lists them.
**Because.** holes #1, closure adopted. Q4 fits it: `Portion` is protected and not carried, so the redacted read is a Document decision plus a Portion `scope`.
**Consequences for v9.** REFERENCE §6 gains a "Matching" paragraph with the three rules and the `object_type/1` and `carries/1` declarations (the same macro as D12). PLAN §The seam: "refuses any call on a protected schema that carries neither a decision for that schema's object type nor a named exemption". Statement prints: protected schemas, unprotected schemas, carried relations. Tier 1 sweep gains cases: wrong object type refused; preload without decision refused; carried preload allowed; nested association write of another protected schema refused. Affects `turnstile_core`, `turnstile_example` (declares object types on Document, Portion, Program, Assignment, OfficeRole, Marking; lookup tables such as Category and Country stay unprotected).

### D11. Exemptions are declared, not only per call
**Decision.** Besides the per-call `{:exempt, reason}` option, `%Turnstile.Config{}` carries a declared exemption table keyed by schema or table and by caller module, printed in the statement with reasons. A library-internal exemption kind covers writes the library itself makes: the ledger events and counter tables, the projector checkpoint, genesis, and the owner-role repo (D15).
**Because.** holes #3, closure adopted. Under D10 `schema_migrations`, `oban_jobs`, and other framework tables declare no object type and pass; the declared table is for protected schemas written by code the application cannot edit.
**Consequences for v9.** REFERENCE §6: `%Turnstile.Exemption{on: schema | table, caller: module | :any, reason: String.t()}`; the library kind is set by library code through the `turnstile:` option and never listed in the audit-mode inventory. CODE §2 option schema: `turnstile:` accepts `%Decision{}`, `{:exempt, reason}`, or `{:exempt, :library}` (the last accepted only from `Turnstile.*` callers, checked by the seam). TESTING §6 committed-repo truncation runs through the owner-role repo. Affects `turnstile_core`, `turnstile_ledger`, `turnstile_fga`.

### D12. The fact event has a payload and the mapping has a macro
**Decision.** A fact event is `%Turnstile.FactEvent{kind, subject_ref, object_ref, attribute, old, new, position, operation_id, at, by}` with `kind` one of `:subject_attribute`, `:object_attribute`, `:relationship`, `:policy_version`. A fact schema declares its mapping with a macro: per column, the kind, the subject column, the object column, the element type for set-valued columns; per row, what insert and delete mean (a relationship row's existence is the grant, its attribute columns are attributes of the relationship).
**Because.** holes #6, closure adopted. Replay, reconcile, and the tuple mapping all need `old` and `new`.
**Consequences for v9.** REFERENCE §8 first bullet rewrites around the macro; REFERENCE §5 becomes the `:policy_version` kind's payload. PLAN §Facts: "a fact schema declares, column by column, which of the four kinds a change is" and names `old` and `new`. CODE §2 Events: the per-kind payload structs are the four above. `turnstile_example` writes the CUI mapping (Assignment and OfficeRole rows are relationships with a `role` attribute; `Marking.controls` and `Marking.list` are set-valued and emit one event per element; `User.employment` and `User.nationality` are subject attributes; `Document.decontrol`, `Document.marking`, `Portion.marking` are object attributes); OPENFGA.md:115's "already" claim is replaced by this mapping. Frozen at S1 (D46).

### D13. The xmin reader is gone
**Decision.** Closed by D6. No xmin reader, no `Dialect.Generic` fixed lag, no unit question.
**Because.** holes #2; owner-answers Q5.
**Consequences for v9.** REFERENCE §9 and §11 as in D6. The Tier 1 interleaved case asserts a reader from position N sees every position above N once the writers commit. Affects `turnstile_ledger`.

### D14. Revocation latency is measured on the committed repo and reported, never asserted
**Decision.** A committed-repo Tier 1 case per adapter measures latency with `System.monotonic_time/1` from the revoking write's commit to the first denied check, polling with the test helper whose interval is printed as the floor, and writes the number and its components into the results file (D16). Components absent from the test environment (replica lag, cache) print "not measured". C12 is compared in the statement and never asserted in CI.
**Because.** holes #5, closure adopted.
**Consequences for v9.** REFERENCE §3 C12: "the statement compares the measured latency with the configured maximum; no test asserts it". REFERENCE §4: "measured revocation latency" leaves the declaration and becomes evidence; the Postgres note loses "the adapter measures replica lag" in favour of "printed not measured unless a replica is configured". REFERENCE §7 "Numbers, not gates" keeps its last sentence. TESTING §6 committed list gains the latency case. Components measured: commit (all), projector drain (`turnstile_fga`, from checkpoint advance), policy propagation (`turnstile_cerbos`, from a policy publish). Affects `turnstile_core` (the case template), every adapter, `turnstile_assess`.

### D15. `around_query/3` and the owner-role repo
**Decision.** The seam gains a fourth extension point, `around_query(query_or_changeset, decision, fun)`, an optional adapter callback the seam calls for every mediated query and write. `turnstile_postgres` uses it to open a transaction when none is open and run `set_config/3` for the subject's session settings on every call, so two subjects in one transaction each set their own. Reconcile, genesis, and test truncation run through a declared owner-role repo: the application's second Repo module, `use Turnstile.Repo, role: :owner`, which `UnmediatedRepo` accepts, the seam treats as wholly library-exempt, and the statement prints.
**Because.** holes #10, closure adopted; the owner-role repo is reconciled with #3's `UnmediatedRepo` rule by declaring it rather than allowing an un-extended Repo.
**Consequences for v9.** REFERENCE §6 lists four extension points: `prepare_query/3`, write overrides, raw wrap, `around_query/3`. REFERENCE §4 Postgres note: session settings by `set_config` inside `around_query`; a call outside a transaction gets one per call. `%Turnstile.Config{}` gains `owner_repo`. TESTING §3 step 4: `Turnstile.TestRepos.Owner` is an owner-role repo in this sense. Affects `turnstile_core`, `turnstile_postgres`, `turnstile_ledger`, each thin app (declares `Example.OwnerRepo` configuration).

### D16. Generator inputs: a formatter, a results file, a body and an evidence file
**Decision.** `turnstile_assess` ships an ExUnit formatter that writes `results.json` (scenario id, outcome, skip reason, capability, latency measurements) per run. The statement is two files per thin app: `statement.md`, deterministic, committed, and diffed by CI with `git diff --exit-code` after regeneration; `evidence.json`, volatile (commit, date, versions, latency, run id), regenerated per run and committed with the body whenever the body is regenerated, never diffed. Declarations are Elixir modules read by the generator at compile time of the thin app.
**Because.** holes #4; the results-file half is adopted, the tag-diff half is moot under D3 (owner-answers Q2b: one statement per thin app, regenerated on every pull request).
**Consequences for v9.** PLAN §Evidence: name the formatter and the two files. REFERENCE §12 gains the `results.json` schema and the statement file layout `apps/example_<a>/statement/{statement.md,evidence.json}`. TESTING §7: each thin-app job runs Tier 2 with the formatter, then `mix turnstile.assess`, then the diff. The README's four statements are the four bodies, included by reference. Affects `turnstile_assess`, all four thin apps.

### D17. Runtime adapter binding
**Decision.** Closed by D7.
**Because.** holes #7; owner-answers Q6.
**Consequences for v9.** As D7.

## Holes that will cause rework

### D18. The head read is one query and shape counts are per adapter and mode
**Decision.** In ledger mode Ecto every port call reads the counter row once; that is one query, counted explicitly. In mode none there is no head and `position` is `nil`. Shape counts are stated per adapter and per ledger mode. "Database-free" is reworded as "reaches the database only through the ledger behaviour and `around_query/3`".
**Because.** holes #9, closure adopted; D6 makes the head read a single-row select.
**Consequences for v9.** REFERENCE §7 shape tests become a table with one row per (adapter, ledger mode) for the scoped `all` case: code and Cerbos under Ecto, two (head, query); under none, one; Postgres under Ecto, three (`set_config`, head, query); OpenFGA under Ecto, three (head, checkpoint, query). PLAN §Adapters "every adapter's decision half is database-free" and §The line "touch no database" are reworded as above; the `boundary` rule keeps `authorize`, `check`, `batch`, `explain`, `review` off `ecto_sql`. Affects `turnstile_core`, every adapter.

### D19. Exhaustiveness in `@after_compile`
**Decision.** The seam's exhaustiveness check runs in `@after_compile` over `module.__info__(:functions)`; only the overrides and `prepare_query/3` are defined in `@before_compile`. The after-compile check also asserts that every write-bucket and raw-bucket function's definition is the one core injected.
**Because.** holes #14, closure adopted; `Module.definitions_in/1` in a before-compile hook cannot see what the adapter's hook defines afterwards.
**Consequences for v9.** REFERENCE §6 "Exhaustiveness at compile time" and "Injected last" rewrite; the ⟨verify⟩ on hook ordering stays as a Tier 1 case, and the sentence "if ordering defeats the wrap, the raw bucket falls to the static check alone" is deleted because the after-compile check fails the build instead. CODE §4 Reflection: `__info__/1` in `@after_compile` is one of the allowlisted uses. Affects `turnstile_core`.

### D20. Old values come from a locked re-read; upserts on fact schemas are refused
**Decision.** For a single-row update or delete on a fact schema the seam re-reads the row under the dialect's lock clause inside its own transaction and takes `old` from the re-read, not from the changeset's `data`. `insert`, `insert_all`, and `insert_or_update` with `on_conflict:` on a fact schema are refused with a pointer to the bulk API.
**Because.** holes #16, closure adopted.
**Consequences for v9.** REFERENCE §8: add the re-read and the refusal. REFERENCE §6 write bucket names upserts. REFERENCE §7 single-row fact write count becomes "the re-read, the write, one ledger insert". Affects `turnstile_core` (refusal), `turnstile_ledger` (re-read through the dialect).

### D21. Cascading foreign keys into fact schemas are caught in the catalog, not the helper
**Decision.** `turnstile_ledger` ships a catalog check that reads foreign keys with `ON DELETE CASCADE` or `SET NULL` into fact schemas; it runs at genesis and in the ledger's Tier 1 case and refuses unless each such key is declared. Declared ones print in the statement as drift sources with the reconcile interval as their window.
**Because.** holes #17. Differs from the suggested migration-helper refusal because a helper sees only the DDL it wrote; the catalog sees every foreign key however it was created.
**Consequences for v9.** REFERENCE §10 Ecto-ledger claim adds "except declared cascades, listed with their window"; REFERENCE §11 gains a "cascade query" row (Postgres: `pg_constraint`; Generic: information schema). The example's migrations use no cascades into fact schemas. Affects `turnstile_ledger`, the thin apps' migrations.

### D22. Head under interleaving
**Decision.** Closed by D6: the head is the counter row's committed value, every position at or below it is committed, and replay to the head is exact.
**Because.** holes #13; owner-answers Q5.
**Consequences for v9.** PLAN §The ledger: "replay is exact to the head". REFERENCE §10 Ecto-ledger claim: "replay exact after reconcile" stays for out-of-band drift only.

### D23. Projection cases run committed and drive a synchronous drain
**Decision.** The three projection cases carry `@tag :committed`. The projector exposes `drain_once/1`, synchronous, which tests drive; the drain interval belongs to a long-lived projector process that CODE lists beside the reconcile scheduler.
**Because.** holes #8, closure adopted; nothing commits inside a sandbox, so a reader of committed positions (D6) has nothing to read there.
**Consequences for v9.** TESTING §6 committed list gains the projection cases; the OpenFGA paragraph's "drains from the sandboxed ledger" becomes "drains from the committed ledger through `drain_once/1`". CODE §4 Processes: "the reconcile scheduler and the projector". REFERENCE §13 projection cases cite the tag. Affects `turnstile_fga`, `turnstile_core` (case template).

### D24. Checkpoint per acknowledged write; drain by diff
**Decision.** The projector advances its checkpoint after every acknowledged `Write` call. The drain computes, per touched object, the difference between the tuples the fold requires and what `Read` returns, and writes only that difference; it tolerates no errors. A decontrol change is a read-diff-write, not delete-and-rewrite.
**Because.** holes #12, closure adopted.
**Consequences for v9.** REFERENCE §4 OpenFGA note and OPENFGA §4 first bullet rewrite: "reads before it writes" only. The ⟨verify⟩ whether FGA keys a tuple on condition context stays for S10. Affects `turnstile_fga`, `example_fga` (tuple mapping row for decontrol).

### D25. Rebuild into a fresh store
**Decision.** `rebuild/1` takes the projector's configuration, creates a store, publishes the pinned model, folds from position zero into it, and returns the new store id; serving continues from the old store until the application swaps `store_id` in config, which the statement prints as a dated change.
**Because.** holes #19, closure adopted.
**Consequences for v9.** REFERENCE §4 OpenFGA note "minutes, offline, once" becomes "minutes, beside the serving store, then a swap". `Turnstile.Projection` callback `rebuild/1` returns `{:ok, store_ref}`. Affects `turnstile_fga`, `turnstile_core` (behaviour).

### D26. Postgres `check` for writes and the per-rule mechanism table
**Decision.** `example_postgres` carries a per-rule table naming the mechanism for each of C1 to C13 (policy, write gate, session setting, or application code). `check` for a write operation is a `SELECT` of the update policy's `USING` predicate, read from `pg_policy`, under the session settings set by `around_query/3`. An RLS `scope` decision record carries rule `true`, the migration number as policy version, and a hash of the session settings in force.
**Because.** holes #15, closure adopted; placement follows D7.
**Consequences for v9.** REFERENCE §4 Postgres note gains the `check`-for-writes definition; REFERENCE §7 `scope` shape gains the RLS variant; REFERENCE §3's "where the adapters differ" paragraph points to the thin apps' tables. Replay for RLS stays "scratch database". Affects `turnstile_postgres`, `example_postgres`.

### D27. Cerbos derived markings take the `filter` fallback
**Decision.** Under Cerbos, `scope` for rules needing derived markings (C3, and C4 through portions) falls back to `filter` and the thin app records `limited`. Nothing is materialized. An attribute declaration maps a Cerbos attribute name to a column or to a subquery.
**Because.** holes #18, closure adopted; materialization would copy what C3 says is never copied.
**Consequences for v9.** REFERENCE §3 "where the adapters differ" deletes the "or"; REFERENCE §4 Cerbos note gains the attribute declaration shape (`attribute :nationality, column: :nationality`; `attribute :assigned_programs, subquery: ...`). PLAN §Adapters Cerbos line: "its query plan compiles to a `dynamic` over declared attributes; derived markings fall back to `filter`". Affects `turnstile_cerbos`, `example_cerbos`.

### D28. OSCAL output is deferred as a component definition
**Decision.** Deferred by D9. When it returns it is an OSCAL component definition, never a whole SSP, validated with the pinned fedramp-automation constraints named in `sources.exs`.
**Because.** holes #20; owner-answers Q10.
**Consequences for v9.** D42 carries the line. PLAN.md nowhere says "SSP validated against FedRAMP's templates".

### D29. Each adapter ships `priv/conformance/`
**Decision.** Each adapter package ships the artifacts Tier 1's neutral fixture needs under `priv/conformance/`: `turnstile_postgres` the RLS migration for the fixture tables, `turnstile_cerbos` the policies, `turnstile_fga` the model and a tuple mapping module.
**Because.** holes #21, closure adopted. The fixture is core's (two object types, two roles, one attribute, one relationship), so this does not leak the CUI domain into adapter packages and keeps D7's placement rule.
**Consequences for v9.** PLAN §Packages: each adapter line gains "and `priv/conformance/`". REFERENCE §14 or TESTING §6 names the fixture. Affects `turnstile_postgres`, `turnstile_cerbos`, `turnstile_fga`.

### D30. "Unsupported" earns a POA&M row; "enforced elsewhere" does not; the scenario table is written
**Decision.** Capabilities keep three levels. A rule enforced by another component of the same stack (C7 by the seam under code, Cerbos, and OpenFGA) is `native`, with the enforcing component named. "Write gates without application code" is not a rule and never a POA&M row; it is a defense-in-depth note printed for Postgres. Only `unsupported` produces a POA&M row. v9 writes the Tier 2 scenario table: id, sentence, group, controls cited, the C-rule it tests.
**Because.** holes #11. Differs from the suggested fourth category because the mislabeled cell was never a rule; three levels plus a component name is enough.
**Consequences for v9.** REFERENCE §3 last paragraph rewrites; REFERENCE §13 declaration summary drops "write gates unsupported". The scenario table goes into docs/reference.md as a new section beside §3, frozen at S1 (D46). The capability record shape (D35) gains `by: component`. Affects `turnstile_assess`, all four thin apps.

### D31. Two verify items
**Decision.** holes #23 is closed by D8. holes #25: PLAN drops "type checker at the strictest setting" for "every type warning is an error"; CODE §1's claims about what 1.20 infers are checked against the Elixir 1.20 changelog at S1 and cited with the URL.
**Because.** holes #23, #25; toolchain-pins.
**Consequences for v9.** PLAN §Packages engineering sentence; CODE §1 gains a source line.

## Clarity-only holes

### D32. Grouped closures
**Decision.** Each in one line.
- holes #24: refusal raises `Turnstile.Error.Unmediated`; audit mode returns the unscoped result and REFERENCE §6 says so in those words (the adoption guide that would have said it is deferred).
- holes #26: `scope` under a denied precondition returns `dynamic([_], false)` with verdict `:deny`; `%Turnstile.Subject{}` carries `kind: :user | :non_person_entity | :privileged` and the port dispatches on it.
- holes #22: moot under D3.
- holes #27: moot under D1; `CLAUDE.md` is rewritten (D43).
- holes #28: CODE §4 Processes reads "the process dictionary is touched in the seam's dynamic-repo entry and in the test configuration resolver, nowhere else" and "long-lived processes: the reconcile scheduler and the projector"; the code adapter's boot-time policy-version append runs inside a transaction that takes the counter row (D6), so it cannot race across nodes, and in mode none it emits telemetry only; TESTING §3's `NOBYPASSRLS` cite points at REFERENCE §4's Postgres note, which gains the sentence; COMPANION's three-adapter passages are not absorbed (D43).
**Because.** holes §A, §F, §G, §I, §J.
**Consequences for v9.** As listed. Affects `turnstile_core`, `turnstile_code`.

## Lessons from attempt 1 adopted as rules

### D33. A green suite of skipped scenarios is a failure
**Decision.** Every Tier 2 run reports the count of executed scenarios per thin app. CI fails if the count is zero, or if any scenario is skipped without a declared `unsupported` or `limited` capability naming it, or with a reason other than a declared capability or `:needs_ledger` in a mode-none run.
**Because.** repo-lessons A4: after the first attempt's Phase 1, 64 scenarios existed and none had run.
**Consequences for v9.** TESTING §6 gains the invariant as its own paragraph; the formatter (D16) writes the counts; `turnstile_assess`'s lint compares skips against the thin app's capability declaration. Affects `turnstile_assess`, all four thin apps.

### D34. A fake returns a value of the real type
**Decision.** No fake, stub, or in-memory implementation raises where the real implementation returns; `Turnstile.Adapter.Fake`'s `scope` returns a real `dynamic`, its `explain` returns `{:error, %Turnstile.Error.Unsupported{}}` when it does not explain.
**Because.** repo-lessons A2: a stub that raised typed every call site as a certain crash under warnings-as-errors (ADR-0034).
**Consequences for v9.** CODE §4 gains a "Fakes" rule. TESTING §5 fake-adapter row cites it. Affects `turnstile_core`.

### D35. Capability records are function clauses; list literals are typed as the checker allows
**Decision.** A thin app's capability declaration is one function clause per record plus a fallback, never a map lookup; the record is `{level, by: component, note: String.t()}`. A role definition's actions are typed `[atom()]`.
**Because.** repo-lessons A2: the checker read an empty-map lookup as returning only the default, and cannot narrow a list literal from params.
**Consequences for v9.** CODE §6 gains both rows. Affects all four thin apps, `turnstile_code`.

### D36. Optional callbacks are answered at runtime
**Decision.** `explain` is optional; core checks `function_exported?/3` and returns `{:error, %Turnstile.Error.Unsupported{}}` when absent. No function is generated or omitted according to the adapter, so one build serves every adapter.
**Because.** repo-lessons A3; D7 removes compile-time binding and this closes the consequence A3 says v8 left unstated.
**Consequences for v9.** CODE §4 Behaviours gains the sentence. PLAN §The question: "`explain`, optional per adapter, answered unsupported at runtime where absent". Affects `turnstile_core`.

### D37. A fake FGA client, and the answer to ADR-0029
**Decision.** `turnstile_fga` talks to the server through a `Turnstile.Fga.Client` behaviour; an `Agent`-backed fake client in test support is built first and runs the projector's convergence and drift cases without a server. The ledger-as-outbox shape is accepted against ADR-0029 because the ledger is the assessment's system of record; D24 gives the duplicate-write answer and reconcile gives the 3PAO the ledger-versus-engine comparison.
**Because.** repo-lessons A5; delivery-plan S10a already says "against an in-memory fake client first".
**Consequences for v9.** REFERENCE §13 names the behaviour and the fake; PLAN §Decisions gains "the ledger projects into the engine; over engine-owned facts with an outbox (attempt 1's ADR-0029)". Frozen interface at S10 (D46). Affects `turnstile_fga`.

### D38. A schema dump per thin app
**Decision.** Each thin-app CI job dumps `pg_dump --schema-only` after migrations into `priv/schema/<adapter>.sql` and fails on diff against the committed file.
**Because.** repo-lessons A6: the Postgres schema diff is the teaching artifact and nothing else proves it.
**Consequences for v9.** TESTING §7 thin-app job gains the step. Affects all four thin apps.

### D39. Naming audit and translation tables
**Decision.** `docs/glossary-index.md` is re-derived for the new packages, listing every word that carries more than one meaning (context, scope, projection, capability, seam) and the one place each meaning lives. Each thin app's README carries a translation table from the domain's words to the adapter's (Assignment to `member` tuple, marking to policy attribute).
**Because.** repo-lessons A1 and A7 (`term/2`).
**Consequences for v9.** PLAN §Packages documentation sentence names the index; D43 places the file. Affects docs, the thin apps.

### D40. Conformance mechanisms are ported from attempt 1
**Decision.** Port `apps/turnstile_core/lib/turnstile/conformance/{scenario,language_lint,case,provider_case}.ex` from `attempt-1`: the scenario macro that validates `control:` at expansion and skips with the thin app's own note; the AST reader that lints without compiling; `unknown_scenarios/2`; the property-suite seed for `AdapterCase`.
**Because.** repo-lessons A8 and §C.
**Consequences for v9.** TESTING §6 names the macro; `docs/delivery.md` S1 and S2b list the ports. Affects `turnstile_core`, `turnstile_assess`.

### D41. The old decision records are cited, not restored as files
**Decision.** No `docs/adr/`. This file is the log. Where v9 reverses an attempt-1 record (0003 runtime config, 0021 Nix, 0029 outbox, 0030 migrations, 0031 capability placement, 0034 stub build) the entry above says so; the records are readable with `git show fac7683:docs/adr/<file>`.
**Because.** repo-lessons §E; owner-answers Q8 makes one file per decision class the channel.
**Consequences for v9.** PLAN §Packages documentation sentence: "decision records live in `docs/decisions.md`". Delete `docs/adr/` from the layout.

## Deferred, not deleted

### D42. The deferred list
**Decision.** Each returns as its own stage after S12, when the condition holds.
- OSCAL component definition: returns when a customer asks for OSCAL import; validated with the pinned fedramp-automation constraints (D28).
- 20x KSI output: returns when the pinned 20x docs define a results schema the lint can check (holes #20 ⟨verify⟩).
- `--diff <ref>`: returns when two dated statements of one thin app exist to compare; it reads two `evidence.json` files.
- Event-store ledger mode: returns when an event-sourced adopter appears; the ledger behaviour and D12's payload are its contract, so nothing in core changes.
- The adoption guide: returns as educational material after implementation, written from the finished example, never as tags (D3).
**Because.** owner-answers Q10, Q2b.
**Consequences for v9.** PLAN.md gains a "Deferred" section listing these five lines; §Phases stops at what D46 keeps.

## Layout

### D43. Files for v9
**Decision.** The v9 tree holds these files and no others at the top level.
- `PLAN.md` at the repo root, Explanation.
- `docs/reference.md`, `docs/testing.md`, `docs/code.md`: revised from v8's REFERENCE, TESTING, CODE, keeping their section numbers where the content survives so this file's citations still resolve.
- `docs/delivery.md`: How-to, stages and gates, written from D46 and delivery-plan §1.
- `docs/writing.md`: ported from `git show attempt-1:docs/writing.md`; its Modes table's Files column is updated to the v9 files.
- `docs/decisions.md`: this file.
- `docs/handoff.md`: overwritten by every agent (D47).
- `docs/glossary-index.md`: D39.
- `CLAUDE.md`: rewritten from the first line: the vocabulary (subject, object, operation, environment; adapter, never provider; assessment-ready, never compliant), the twelve apps, the gate alias, the banned-word grep, the handoff rule, the question-preamble rule (D49).
- `plan/v8` and `plan/review`: frozen history, never edited.
Absorption of the two v8 files that have no v9 counterpart:
- `plan/v8/COMPANION.md`: §1 to §12 and §14 into PLAN.md's explanation and decisions list where still true (three-adapter passages and Appendix B are dropped); §13 into D42's one line; Appendix A into the package glossaries as the packages appear, and until then into docs/reference.md §12's glossary.
- `plan/v8/OPENFGA.md`: §1 to §5 into docs/reference.md §13 with D23 to D25 applied; §6 into D44; §7 into PLAN.md's decisions list.
- `docs/how-to/bump-sources.md` and `docs/how-to/adopt.md` are not in the layout; the bump procedure becomes a how-to file inside `turnstile_assess` when S2c writes it; the adoption guide is deferred (D42).
**Because.** The orchestrator's layout; owner-answers Q8 for the handoff file.
**Consequences for v9.** Every file declares one Diátaxis mode on line two in italics; the banned-word grep from the handoff gate runs over `docs/`, `PLAN.md`, and `CLAUDE.md`.

### D44. The umbrella
**Decision.** Twelve apps under `apps/`:
- `turnstile_core`: port, structs, clock, ledger and projection behaviours, the seam, Credo checks, boundary rule, `AdapterCase`, the fake adapter, the in-memory ledger, test cluster support.
- `turnstile_ledger`: counter row, events table, migration and genesis helpers, catalog check (D21), bulk fact API, dialects Postgres and Generic, reconcile, replay.
- `turnstile_code`, `turnstile_postgres`, `turnstile_cerbos`, `turnstile_fga`: the adapters, each with its domain-free declaration and `priv/conformance/` (D29); `turnstile_fga` adds the projector, the client behaviour, and the checkpoint migration helper.
- `turnstile_assess`: the generator (markdown profile), the formatter, `results.json`, the lint, pinned sources, `mix turnstile.assess`, `mix turnstile.review`.
- `turnstile_example`: a library app with no application callback: the CUI schemas (Portion included), object-type and fact-mapping declarations, contexts, the redacted read, the hash-chained audit store, `Example.Repo` and `Example.OwnerRepo` (`use Turnstile.Repo`), the router, controllers, the identity-only plug, fixtures, and the scenario tests as test support (`Example.Scenarios`, every scenario present, run by each thin app).
- `example_code`, `example_postgres`, `example_cerbos`, `example_fga`: thin apps, each with its own `config/` (its own `config_path`), its `Application.start/2` that starts `Example.Repo`, the endpoint, Turnstile, and for `example_fga` the projector; the adapter binding in config (D7); the per-rule capability declaration (D7, D35); policies (`example_cerbos`), model and tuple mapping (`example_fga`), RLS policies and write gates (`example_postgres`); `priv/repo/migrations`; `priv/schema/<adapter>.sql` (D38); `statement/` (D16); a test file that runs `Example.Scenarios` under this adapter; a README with the translation table (D39).
Migrations: the working rule "migrations exist only in the example" becomes "library packages ship migration helpers; migrations exist only in the thin apps, one set each". `turnstile_example` ships `Example.Migrations.Domain` (the CUI tables) as a helper the thin app's first migration calls; `turnstile_ledger` ships the counter, events, and genesis helpers; `turnstile_fga` ships the checkpoint helper; `example_postgres` writes its RLS migrations by hand, since they are the teaching artifact.
**Because.** owner-answers Q2a, Q3, Q6; repo-lessons §D (ADR-0030 row).
**Consequences for v9.** PLAN §Packages and conventions replaces its tree. `docs/delivery.md` shard rows follow these directories. `example_code`'s job runs Tier 2 twice, once per ledger mode, so mode none is exercised (D9); the other thin apps run mode Ecto.

### D45. The configuration struct
**Decision.** `%Turnstile.Config{}` is validated once at boot from a `NimbleOptions` schema and is the only runtime configuration the library reads. Its fields, each added by the entry named: `adapter` (D7); `ledger` as `{Turnstile.Ledger.Ecto, repo: module} | :none` (D9); `ledger_counter`, default `"default"` (D6); `owner_repo` (D15); `exemptions` (D11); `seam_mode` as `:enforce | :audit` (D32); `clock`; the caps of REFERENCE §7 (`decision_volume`, `batch_ids_cap`, `rule_cap`, `policy_content_cap`); adapter-specific keys under `adapter_options` (Cerbos address, FGA endpoint, store id, model id, consistency per operation, drain interval, `ListObjects` cap). Tests override any field through `Turnstile.Test.with_config/2`.
**Because.** CODE §2 Configuration; owner-answers Q6; nine entries above each add a field and the plan writer needs them in one place.
**Consequences for v9.** docs/code.md §2 lists the fields; the schema is frozen at S1 (D46). Affects `turnstile_core`, every thin app's config.

### D46. Delivery stages revised
**Decision.** The stage list of delivery-plan §1 is kept with these changes.
- S0: as D8; the gate adds `cerbos --version` printing 0.55.0 and `openfga version` printing 1.19.0 from the fetched and packaged binaries.
- S1: adds D10's matching rules, D12's payload and macro, D11's exemption struct, D15's callback, D30's scenario table, D40's ported modules, D45's schema. Frozen interfaces gain `around_query/3`, `%Turnstile.Exemption{}`, `%Turnstile.FactEvent{}`, the counter table shape, the `results.json` schema, and the scenario table.
- S2a: adds D19 (after-compile check) and D20's upsert refusal. S2b: adds D34 and the latency case template (D14). S2c: adds the formatter (D16) and D33's skip check.
- S3: `turnstile_example` plus `example_code`, built with the seam enforcing from the first commit and depending on S1; no v0, no audit-mode walk. Domain work formerly in S5 (role table, override, re-authentication, `review`) lands here and in S4.
- S4: `turnstile_code`, unchanged.
- S5: deleted (D3).
- S6: one shard around the counter row: table, helpers, genesis, bulk API, dialects, reader, reconcile, replay, the catalog check (D21), the interleaving and lock-cost cases.
- S7: `example_code` in ledger mode Ecto: fact fields declared through D12's macro, genesis migration, history scenarios; the mode-none run stays as the second Tier 2 job (D44).
- S8, S9, S10: adapter package, then thin app, in sequence. S10a builds `Turnstile.Fga.Client` and its fake first (D37); the frozen interface at S10 is that behaviour.
- S11: point-in-time review, drift scenarios, replay per adapter; `--diff` removed.
- S12: the README with the four statement bodies, the schema dumps (D38), the statement diff jobs; OSCAL, KSI, and the adoption job removed (D42).
- delivery-plan §2's worktree and branch discipline is replaced by D47; shards within a stage run in sequence, one agent each, each with its own handoff. §3 (encoding) is moot and not carried.
**Because.** owner-answers Q2b, Q8, Q10; delivery-plan §1 and §2.
**Consequences for v9.** `docs/delivery.md` is written from this entry and delivery-plan §1; every gate is a command and its expected output; every stage's entry names the decisions it implements.

## Process

### D47. Commits and orchestration
**Decision.** Sequential work, one branch (`main` on the orphan line), no worktrees. Each agent commits its own work when done, unsigned (`git -c commit.gpgsign=false commit -F -`). `docs/handoff.md` is written from scratch by every agent, never revised, and overwritten in the same commit: task, what was done, gate command and its result, what the next task needs to know, open problems. The orchestrator reads only that file and the gate output to decide the next task.
**Because.** owner-answers Q8.
**Consequences for v9.** `CLAUDE.md` states the rule; `docs/delivery.md` §2 replaces the worktree discipline with it; no plan file describes shards as parallel.

### D48. Review checkpoints
**Decision.** One pause, after plan v9 and its companions are written; the owner reads and approves or edits. After that the stages run to completion in sequence, each gated by the orchestrator, reporting at the end or when blocked.
**Because.** owner-answers Q9.
**Consequences for v9.** `docs/delivery.md` opens with the checkpoint; no stage after it waits on the owner unless its gate fails or it needs an admin action (D8's installer).

### D49. Questions carry their preamble inside the question
**Decision.** Any question put to the owner carries its layman preamble inside the question text itself; prose before the dialog is not seen.
**Because.** owner-answers process note.
**Consequences for v9.** `CLAUDE.md` states the rule.
