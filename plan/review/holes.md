# Plan v8 — where it hand-waves
*Mode: Reference. Produced 2026-09-07 by a review agent reading every file in `new-plan/`. Paths are relative to `new-plan/`; `deps/…` is the repo's `deps/` (pinned Ecto 3.14.2, checked where an Ecto fact mattered). Ranks are overall; holes are grouped by area. Deliberate omissions recorded in the archive (filter language, projection lag, Docker, per-row audit) were not counted.*

**Top ten by rank:** 1 decision-to-query matching (seam) · 2 xmin reader skips events (ledger) · 3 no exemption path for framework/library callers (seam) · 4 generator inputs and the tag-diff job (generator) · 5 latency harness and the C12 gate (latency) · 6 fact-mapping declaration has no shape (facts) · 7 compile-time adapter binding vs four adapters in one test run · 8 projector in the sandbox (projector) · 9 head-position read vs "one query" shape tests and "database-free decisions" · 10 SET LOCAL has no place to run.

---

## A. The Repo seam

### #1 Which decision applies to which query is never defined — blocks implementation
PLAN.md:65, COMPANION.md:107, REFERENCE.md:90, REFERENCE.md:99.
The decision travels as the `turnstile:` option (CODE.md:53, COMPANION.md:107), so process dictionary questions are moot, but the plan never states the rule that ties a `%Decision{}` to the query it arrives on. A decision is for one object type; a query may root on a join table, a lookup table, or a schema other than the decision's; a `dynamic([d], …)` binds to position 0 regardless. Preloads: on the pinned Ecto the preloader calls `Ecto.Repo.Queryable.all` (deps/ecto/lib/ecto/repo/preloader.ex:433) which does call `repo.prepare_query` (deps/ecto/lib/ecto/repo/queryable.ex:224) with the preload's own opts, so `Repo.preload(doc, :portions, turnstile: doc_decision)` either applies Document's dynamic to the Portion query or is refused; the ⟨verify⟩ at REFERENCE.md:99 resolves yes, but the harder question survives. Nested association writes go through `apply(repo, action, [changeset, opts])` (deps/ecto/lib/ecto/association.ex:930, 1257, 1554), so a parent's decision silently authorizes child-row writes of another schema. Join-based preloads and multi-source queries are one query with several schemas. "Every query" also means every lookup query (countries, categories) needs a decision or an exemption; nothing says whether unprotected schemas exist.
*Close it with:* a schema is protected iff it declares an object type; the seam refuses when the decision's object type is not the query's root source; preload and association queries need their own decision or a declared carried relation.

### #3 Exemptions exist only as a per-call opt, so framework and library writes cannot be exempted — blocks implementation
COMPANION.md:107, CODE.md:53, REFERENCE.md:101, TESTING.md:26, TESTING.md:65.
`Ecto.Migrator` writes `schema_migrations` through `repo.insert` and `repo.delete_all` (deps/ecto_sql/lib/ecto/migration/schema_migration.ex:59, 66); Oban (in `deps/`) calls the application Repo with its own opts; the ledger's fact-event `insert_all` (REFERENCE.md:138), the projector checkpoint (OPENFGA.md:137), the example's audit store, and the Owner test repo's truncation (TESTING.md:65) all hit the seam with no `turnstile:` key. None of these call sites can be edited to carry `{:exempt, reason}`, and `UnmediatedRepo` (REFERENCE.md:101) forbids a second, un-extended Repo as the escape hatch. The `NoRawSQL` allowlist (REFERENCE.md:101) covers raw SQL only, not Repo functions.
*Close it with:* a declared exemption table keyed by table/schema and by caller module, printed in the statement, plus a library-internal exemption kind for the ledger, checkpoint, and migrator.

### #9 The ledger-head stamp and "database-free decisions" contradict the shape tests — will cause rework
REFERENCE.md:114, REFERENCE.md:127, PLAN.md:85, PLAN.md:93, OPENFGA.md:147.
"The position is stamped at decision time" needs a read of the ledger head (a query) per port call, and FGA's `applied_position` needs a read of the checkpoint table; yet PLAN.md:85 says every adapter's decision half is database-free and PLAN.md:93 puts `authorize`/`check`/`batch` above the database line, and REFERENCE.md:127 counts "a scoped `all` over 1,000 rows: one query". Under Postgres RLS the same call also needs `SET LOCAL` (see #10), so the count is three statements, not one, and differs per adapter and per ledger mode.
*Close it with:* define head as one extra query counted explicitly, state shape counts per adapter and ledger mode, and reword "database-free" as "reaches the database only through the ledger behaviour".

### #14 Compile-time exhaustiveness can silently miss adapter-injected functions — will cause rework
REFERENCE.md:95, REFERENCE.md:97, deps/ecto/lib/ecto/repo.ex:266.
Ecto registers `@before_compile adapter` inside `use Ecto.Repo`, before `use Turnstile.Repo` registers core's hook. The plan's ⟨verify⟩ covers whether core's *overrides* wrap `query/3`; it does not cover the exhaustiveness check itself: `Module.definitions_in/1` in a `@before_compile` hook sees only functions defined so far, so if the adapter's hook runs after core's, `query/4`, `to_sql/2`, `explain/3`, `disconnect_all/1` are never seen and the "fails compilation on any function it has not classified" claim (PLAN.md:67) is false for exactly the raw bucket the plan worries about, with no compile failure to tell you.
*Close it with:* do the exhaustiveness check in `@after_compile` over `module.__info__(:functions)` and keep only the overrides in `@before_compile`.

### #24 "Refuses" and audit mode have no defined return value — clarity only
PLAN.md:35, PLAN.md:65, CODE.md:93.
`Repo.all` returns a list, so refusal must raise, which is fine if a missing decision is "a programming error", but the plan never says so; and in audit mode, "logs instead of refusing" returns an unscoped result, which is a data leak the adoption guide (COMPANION.md:298) should name.
*Close it with:* refusal raises `Turnstile.Error.Unmediated`; audit mode returns the unscoped result and the guide says so.

## B. Fact recording

### #6 The fact mapping has no declared shape — blocks implementation
PLAN.md:45, REFERENCE.md:134, OPENFGA.md:115, OPENFGA.md:117–133, REFERENCE.md:108.
"A fact schema declares which of its columns are facts" cannot express the four kinds: an `Assignment` row *is* a relationship (row existence, not a column), and its `role` is an attribute of that relationship; `Marking.controls` and `Marking.list` are set-valued, so one "changed field" is N grants and revokes. The tuple mapping (OPENFGA.md:132 "delete and rewrite"), reconcile's fold, and replay all need the previous value, and nothing says a fact event carries `old` and `new`. OPENFGA.md:115 says the example's mapping "already" turns schema changes into the four kinds; it exists nowhere.
*Close it with:* specify the fact event payload as `{kind, subject_ref, object_ref, attribute, old, new}` and the declaration macro (per column: kind, subject column, object column, element type for sets, what delete means).

### #16 Old values, stale changesets, and upserts — will cause rework
REFERENCE.md:134, REFERENCE.md:136, REFERENCE.md:91.
A single-row update takes "old" from the changeset's `data`, which is whatever the caller loaded earlier; under concurrency the ledger records a transition that never happened, while `bulk_update` compares against the database. `insert`/`insert_all` with `on_conflict:` updates fact fields of existing rows with no changeset and no old value, and `RETURNING` cannot say which rows were inserted versus updated; the write bucket (REFERENCE.md:91) does not mention upserts.
*Close it with:* the seam re-reads the row `FOR UPDATE` inside its transaction for fact schemas, and refuses `on_conflict` upserts on fact schemas in favour of the bulk API.

### #17 Database cascades falsify "no fact without an entry" — will cause rework
REFERENCE.md:151, PLAN.md:58, PLAN.md:67.
`ON DELETE CASCADE` or `SET NULL` from Program to Assignment revokes relationships with no Repo call; the seam sees only the parent delete. `on_replace: :delete` is covered (deps/ecto/lib/ecto/association.ex:1257 goes through the Repo), cascades are not, and the only catch is reconcile's interval, which the mode claim at REFERENCE.md:151 does not admit.
*Close it with:* the ledger's migration helper refuses cascading FKs into fact schemas, or the statement lists each as a drift source with the reconcile interval as its window.

## C. Ledger positions

### #2 The xmin reader as described skips events — blocks implementation
REFERENCE.md:144, REFERENCE.md:164, PLAN.md:202.
"Reads only positions below the oldest position still held by an in-flight transaction — snapshot `xmin` against each row's transaction id" conflates xid order with position order, and they are independent: `nextval` is evaluated when the row is built, the xid is assigned at `heap_insert`, and either can happen first across two transactions. Transaction A takes position 10 and xid 6 while B, xid 5, takes position 11 and commits; the snapshot's xmin is 6, B's row passes the filter, the checkpoint advances to 11, and A's position 10 commits behind it. No filter over *visible* rows can bound positions held by invisible ones. Separately, `xmin` is a 32-bit `xid` and `pg_current_snapshot()` is `xid8`; the comparison needs a stored `pg_current_xact_id()` column. The Tier 1 interleave case passes or fails on an interleaving it cannot control. `Dialect.Generic`'s "fixed lag" has no unit (positions or time).
*Close it with:* either order the ledger by `(xid8, seq)` with the checkpoint on xid8 (what the snapshot actually bounds), or make the counter row the Postgres default; and give Generic's lag a unit.

### #13 `head_position` under interleaving makes replay inexact — will cause rework
PLAN.md:39, PLAN.md:51, REFERENCE.md:114, REFERENCE.md:151.
If the head is the max visible position at decision time, "fold up to head" at replay includes lower-positioned events that committed after the decision, so "replay exact after reconcile" is not delivered by the mechanism as written; if the head is the reader's stable frontier, decisions stamp a position that lags the state the adapter actually read.
*Close it with:* define head as the stable frontier and say replay is exact to the frontier, not to the instant.

## D. The OpenFGA projector

### #8 The projector cannot drain a sandboxed ledger — will cause rework
TESTING.md:71, TESTING.md:65, OPENFGA.md:137, CODE.md:105.
"The projector under test drains from the sandboxed ledger into the test's store", but the visibility-safe reader admits only rows whose xid is below the snapshot's xmin; inside a sandbox transaction every event the test wrote carries the test's own, still-open xid and is never released, so the measured-lag and re-drain cases cannot pass as tagged. The committed-repo list at TESTING.md:65 omits the projection cases. Also, a drain interval implies a long-lived process, which CODE.md:105 forbids (only the reconcile scheduler).
*Close it with:* projection cases run `@tag :committed`, the projector exposes a synchronous `drain_once/1` the test drives, and CODE.md lists the projector beside the scheduler.

### #12 Checkpoint atomicity, batch failure, and conditional tuples — will cause rework
OPENFGA.md:137–139, REFERENCE.md:72, OPENFGA.md:132.
The checkpoint is in the application database and tuples are in FGA, so a crash between batches leaves tuples applied past the checkpoint and `applied_position` understated. "Tolerates exactly those two errors" ignores that an FGA `Write` is atomic per call and rejects the whole batch on one duplicate, so tolerance means retrying tuple-by-tuple, unspecified. "Delete and rewrite the flag tuples with the new parameter" replayed after partial application deletes nothing and then hits "already exists" on the old-parameter tuple, so tolerance preserves the stale decontrol date ⟨verify whether FGA keys a tuple on condition context⟩.
*Close it with:* advance the checkpoint after every acked `Write` call, and make the drain compute a diff against `Read` for the touched objects instead of tolerating errors.

### #19 Rebuild while serving — will cause rework
OPENFGA.md:140, REFERENCE.md:72.
"Minutes, offline, once" does not say what `Check` returns during those minutes (an empty store fails closed for everyone) or what `rebuild/1`'s argument is.
*Close it with:* rebuild into a fresh store and swap the configured store id.

## E. Revocation latency

### #5 The harness is unspecified and C12 is a timing gate the plan forbids — blocks implementation
PLAN.md:85, REFERENCE.md:130, REFERENCE.md:53, PLAN.md:209, TESTING.md:60, TESTING.md:53, TESTING.md:65, REFERENCE.md:67, REFERENCE.md:69.
"Measured end to end by Tier 1" and "decomposed into commit, projector drain, policy propagation, replica lag, and cache" needs per-component instrumentation nowhere described; the test cluster has no replica (TESTING.md:23), so "the adapter measures it" (REFERENCE.md:69) cannot happen in Tier 1. The clock is a Mox behaviour, and which clock times the poll is unstated; `poll/2`'s interval is the measurement's floor. REFERENCE.md:130 says the committed repo, TESTING.md:65's committed list omits it. The number is part of the adapter's *declaration* (REFERENCE.md:67), static data, with no route from a test run into it. And C12 says the measured latency "must be below" the configured maximum, which is a timing assertion in CI, contradicting PLAN.md:209 and REFERENCE.md:130 "reported, not bounded".
*Close it with:* a committed-repo test using `System.monotonic_time/1` that writes `results.json`, read by the generator; components absent from the environment print "not measured"; C12 is compared in the statement and never asserted.

## F. `scope`

### #10 `SET LOCAL` has no place to run — blocks the Postgres adapter
REFERENCE.md:69, COMPANION.md:95, TESTING.md:41, REFERENCE.md:92.
`prepare_query/3` can only return a rewritten query; it cannot issue `SET LOCAL`. So the Postgres adapter must wrap every mediated call in a transaction and run a raw statement first, which is the raw bucket that demands an exemption, and the seam has no hook for "before the query, inside the transaction". Nothing says what happens to a call outside a transaction, how two subjects in one transaction (an override then a normal read) are handled, or how reconcile reads all rows past `FORCE ROW LEVEL SECURITY` (an owner-role Repo, which #3 forbids).
*Close it with:* a fourth seam extension point, `around_query/3`, that the Postgres adapter uses to open the transaction and call `set_config/3`; reconcile runs through a declared owner-role Repo.

### #15 Postgres `check` for writes and for C8–C10 is undefined — will cause rework
COMPANION.md:89, REFERENCE.md:56, REFERENCE.md:63, PLAN.md:41.
`scope` returns `true` and the recorded rule is `true`, so "replay recomputes rows from position plus rule" (PLAN.md:41) does not hold for RLS; REFERENCE.md:69 concedes the scratch database, but the decision record shape (REFERENCE.md:110) should say what an RLS scope record carries. `WITH CHECK` runs only at write time, so how `authorize(subject, :change_marking, doc)` answers before the write, and which of C8 (session fact), C9, C10 Postgres does natively versus in code, is unstated; "verdict only" is not a mechanism.
*Close it with:* a per-rule table for Postgres naming the mechanism, and `check` for writes defined as a `SELECT` of the update policy's `USING` predicate under `SET LOCAL`.

### #18 Cerbos derived markings: an undecided "or" that contradicts C3 — will cause rework
REFERENCE.md:56, COMPANION.md:239, REFERENCE.md:44, PLAN.md:165.
"Effective controls are materialized per Document *or* `scope` falls back to `filter` and records limited" is an open decision not marked ⟨open⟩. Materialization copies implied controls into a column, which C3 forbids ("Nothing is copied"), and raises whether that column is a fact field, double-ledgering every category change. How a Cerbos plan over `request.resource.attr.*` becomes a `dynamic` with subqueries (C1 needs membership tests) depends on the "attribute declarations" at PLAN.md:165, which have no shape.
*Close it with:* the example takes the `filter` fallback and records limited; an attribute declaration maps a Cerbos attribute name to a column or a subquery.

### #26 `scope` under a missing caller fact, and "their own paths" — clarity only
PLAN.md:31, PLAN.md:35.
"A missing caller fact denies" has no stated meaning for `scope`; the narrowing property allows `dynamic([_], false)` but the plan does not say that is the answer or what verdict it records. "Privileged users and non-person entities take their own paths" names no path.
*Close it with:* `scope` on a denied precondition returns `dynamic([_], false)` with verdict `:deny`; the subject struct carries a kind and the port dispatches on it.

## G. The generator and the tag job

### #4 Inputs have no format and the per-tag diff cannot be clean — blocks implementation
PLAN.md:122, COMPANION.md:276–278, TESTING.md:75, TESTING.md:82.
No declaration file format, no results source (ExUnit formatter, JSON file, or the test process itself), no route for the measured latency. The statement carries "commit, date, versions, latency" (PLAN.md:122), so a regenerated statement never equals the committed one and the `tags` job fails by construction unless volatile fields are excluded, which is not stated.
*Close it with:* an ExUnit formatter in `turnstile_assess` writing `results.json`; the statement split into a deterministic body and a volatile evidence file; the diff covers the body.

### #20 OSCAL "SSP validated against FedRAMP's templates" — will cause rework
PLAN.md:184, PLAN.md:122, COMPANION.md:266.
A library cannot emit a complete SSP (system metadata, boundary, users, interconnections), and FedRAMP's constraint set validates whole documents; the artifact a library can validly emit is an OSCAL component-definition the provider imports. The validator is unnamed ⟨verify: oscal-cli plus the fedramp-automation constraints, at a pinned version⟩; whether the 20x docs define a results schema at all is ⟨verify⟩.
*Close it with:* emit a component-definition, validate with the pinned fedramp-automation constraints, and name the pin in `sources.exs`.

### #22 Tags are immutable, the list is not linear, and the CI closure differs per tag — clarity only (partly ⟨open 3⟩)
PLAN.md:146, TESTING.md:82, TESTING.md:83, OPENFGA.md:161.
TESTING.md:82 says `v0…v10b`, omitting `v10c`; `v10a/b/c` branch from `v9`, so "the next tag" is a graph. A pinned-source bump or a generator change invalidates every committed statement and a tag cannot be amended; whether HEAD's generator or the tag's regenerates is unstated; tags before Phase 5 have no `openfga` in their flake.
*Close it with:* regenerate with HEAD's generator against a worktree of each tag and commit statements under HEAD's `docs/statements/<tag>/`.

## H. Adapter binding, environment, toolchain

### #7 Compile-time adapter binding vs four adapters in one test run — blocks Tier 1
PLAN.md:172, CODE.md:57, TESTING.md:73, TESTING.md:69, PLAN.md:83.
`Application.compile_env/3` binds one adapter per build, but Tier 1 is `use Turnstile.Conformance.AdapterCase, adapter: …` per adapter as async modules in one `mix test`, and "everything runs by default" for `:cerbos`, `:postgres`, `:fga`. The config-override pattern (TESTING.md:54) covers addresses and caps, not the adapter module.
*Close it with:* the port reads the adapter from `%Turnstile.Config{}` at runtime; `compile_env` is reserved for the example's generated per-operation functions.

### #21 Tier 1 needs per-adapter artifacts for the neutral fixture — will cause rework
COMPANION.md:282, PLAN.md:120, OPENFGA.md:30–109.
Cerbos needs policies, FGA needs a model and a tuple mapping, Postgres needs RLS migrations, all for Tier 1's two-object fixture; only the CUI model exists and no package lists these as deliverables.
*Close it with:* each adapter ships `priv/conformance/` for the Tier 1 fixture.

### #23 Nix pins asserted without a source; OTP 28 vs the tree's OTP 29 — ⟨verify⟩
PLAN.md:172, TESTING.md:13, CODE.md:65, TESTING.md:12.
PLAN.md:172 states the flake pins Cerbos and OpenFGA; TESTING.md:13 marks nixpkgs ⟨verify⟩; neither says where it was verified, which CLAUDE.md requires. The plan pins OTP 28 and bans `.tool-versions`, while the tree's `.tool-versions` pins OTP 29.0.6 verified 2026-09-03 against a URL; the plan does not say why it steps back a major or what happens to that file.

### #25 "Type checker at the strictest setting" — ⟨verify⟩
PLAN.md:172, CODE.md:61, CODE.md:6, CODE.md:22.
CODE.md:61 says "Elixir has no `strict: true`", contradicting PLAN.md:172. CODE.md:6's claims (protocol dispatch, non-atom-key maps, cross-application inference) and the `infer_signatures` default are ⟨verify⟩; nothing else in the plan depends on them beyond the verified-bug examples at CODE.md:14, so the risk is the prose, not the design.

## I. The example across adapters

### #11 "Unsupported" produces a POA&M row for rules that are enforced — will cause rework
PLAN.md:122, REFERENCE.md:56, OPENFGA.md:111, OPENFGA.md:157, OPENFGA.md:160, REFERENCE.md:8–19.
C7 is enforced by the seam under code, Cerbos, and FGA (OPENFGA.md:111), yet "write gates unsupported" earns a POA&M row, which a 3PAO reads as an open weakness in three of four statements. No scenario or control for "the database refuses without application code" appears in §1. The Tier 2 scenario list itself is absent from v8; CLAUDE.md points to `apps/turnstile_example/README.md`, which describes the old Labels/Compartments domain.
*Close it with:* separate "unsupported" (POA&M) from "not applicable, enforced elsewhere" (origination note only), and write the scenario table.

### #27 The plan does not say what happens to the existing tree — clarity only
Existing apps are `turnstile_rbac`, `turnstile_rebac`, `turnstile_openfga`, `Turnstile.Provider` (docs/status.md), CLAUDE.md says "Providers own mechanism", and the plan reserves *adapter* over *provider* (PLAN.md:27) and names `turnstile_code` and `turnstile_fga`. An implementer on day one meets a CLAUDE.md that contradicts the plan's vocabulary and a README of sixty-four scenarios for another domain.
*Close it with:* one paragraph on migration from the current tree, and a CLAUDE.md edit.

## J. Smaller conflicts

### #28 Process and state rules that contradict each other — clarity only
CODE.md:105 confines the process dictionary to Ecto's dynamic-repo entry; TESTING.md:54 puts config overrides in it. CODE.md:105 allows one long-lived process; the projector (OPENFGA.md:137) and Cerbos decision-log reconciliation (REFERENCE.md:70) need more. REFERENCE.md:80's boot-time policy-version append races across nodes and has no ledger to consult in mode none. COMPANION.md:6, :338 and Appendix B still describe three adapters and plan v7. TESTING.md:24 cites REFERENCE §4 for `NOBYPASSRLS`, which §4 does not mention.

Every PLAN.md citation of a REFERENCE section otherwise resolves to a section that contains what is promised (§1, §2–3, §4, §5, §6, §7, §8, §9–10, §12). The remaining author-marked ⟨verify⟩ items (`maxTuplesPerWrite` 100, `ListObjects` cap, Cerbos unix-socket support, the PS-4 value, Rev 5 AU-2 wording, enhancement membership) are correctly scoped as verifications rather than holes.
