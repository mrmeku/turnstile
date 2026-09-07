# Handoff: reference v9
*Mode: Reference. What the reference agent did, the gate output, the citation check, what the next agent's files presume, and what is open.*

## Task

Write `docs/reference.md`, the v9 revision of `plan/v8/REFERENCE.md`, absorbing what is still true from `plan/v8/COMPANION.md` and `plan/v8/OPENFGA.md` and applying every decision in `docs/decisions.md`; keep v8's section numbering where `PLAN.md` cites it; drop what the decisions removed; then overwrite this file and commit both. `plan/`, `PLAN.md`, and `docs/decisions.md` untouched.

## Done

`docs/reference.md`, 725 lines, sections §1 to §15 (§3a and §15 new, the rest v8's numbers).

- §1: the group table gains an id-prefix column (`enf`, `lp`, `sod`, `rev`, `aud`, `rvw`, `ia`, `ovr`, `cm`, `inv`); scenario ids are prefix, hyphen, two digits.
- §2: the four controls; the Portion entity, `read` versus `read_redacted`, the redacted read as a Document decision plus a Portion `scope` applied through `preload`, and a per-adapter portion mechanism table ⟨D5⟩ ⟨D10⟩.
- §3: C1 to C13 with C4 restored (write-time union in the domain, tested as a scenario) and C12 as a comparison never asserted; the rule-by-adapter mechanism table with levels and enforcing components ⟨D26⟩ ⟨D27⟩ ⟨D30⟩; capability records as function clauses with a fallback ⟨D35⟩.
- §3a: sixty Tier 2 scenarios as a table (id, sentence, group, controls, what it tests, whether it needs a ledger), including the portion scenarios; the "write gates" note is not a scenario ⟨D30⟩ ⟨D33⟩.
- §4: the comparison table without latency as a declaration; the declaration split between adapter package and thin app ⟨D7⟩; Postgres note with `around_query/3`, `set_config/3`, `check` for writes from `pg_policy`, the RLS scope record, `NOBYPASSRLS`, "not measured" without a replica; Cerbos attribute declaration shape and the `filter` fallback; code adapter's boot-time append under the counter row; OpenFGA projector summary; revocation latency as evidence with its components ⟨D14⟩ ⟨D15⟩ ⟨D24⟩ ⟨D25⟩ ⟨D32⟩ ⟨D37⟩.
- §5: the `:policy_version` payload and the per-adapter table ⟨D12⟩ ⟨D32⟩.
- §6: buckets with upserts named in the write bucket; the three matching rules, `object_type/1` and `carries/1`; the exemption struct and its two kinds with the library kind restricted to `Turnstile.*` callers; the owner-role repo; four extension points; the after-compile check asserting core's definitions; `Turnstile.Error.Unmediated` and audit mode returning the unscoped result; locked re-read; the cascade catalog check; static checks; what the statement prints ⟨D10⟩ ⟨D11⟩ ⟨D15⟩ ⟨D19⟩ ⟨D20⟩ ⟨D21⟩ ⟨D32⟩.
- §7: shapes with the RLS variant and the denied-precondition `scope`; the head read as one query; the shape table per adapter and ledger mode; the single-row fact write count ⟨D18⟩ ⟨D26⟩ ⟨D32⟩.
- §8: the `use Turnstile.Schema` mapping macro with per-column and per-row declarations, the CUI mapping, the event struct, upsert refusal, the bulk API ⟨D12⟩ ⟨D20⟩.
- §9: `turnstile_ledger_counter(name, position)`, the five-step take, commit order is position order, the lock-cost and interleaved cases, the per-test row inside the sandbox ⟨D6⟩ ⟨D13⟩ ⟨D22⟩.
- §10: Ecto and none; the event-store ledger mode as one deferred line; genesis, grant, catalog check ⟨D9⟩ ⟨D21⟩ ⟨D22⟩.
- §11: Postgres and Generic; the reader row reads "counter row; a watermark reader is a later option"; counter-take and cascade-query rows.
- §12: pinned sources; bump procedure with the how-to deferred to `turnstile_assess`; the toolchain table with each pin's "where" from `plan/review/toolchain-pins.md` ⟨D8⟩; generator inputs, the formatter, a `results.json` example, the skipped-scenario invariant, statement files and the CI order with the schema dump, the translation table, SSP vocabulary, the assessment glossary, and COMPANION Appendix A's terms with owners ⟨D16⟩ ⟨D33⟩ ⟨D38⟩ ⟨D39⟩ ⟨D43⟩ ⟨D44⟩.
- §13: OPENFGA.md's §1 to §5 absorbed: the concept table, the full model with a `portion` type and `can_read_redacted`, the rule-by-rule paragraph, the tuple mapping with decontrol as read-diff-write, the client behaviour and the `Agent`-backed fake, the projector with checkpoint per acknowledged write, drain by diff, rebuild into a fresh store, the domain-free declaration summary, the three `@tag :committed` projection cases ⟨D7⟩ ⟨D23⟩ ⟨D24⟩ ⟨D25⟩ ⟨D34⟩ ⟨D37⟩.
- §14: the environment summary, `priv/conformance/` and the neutral fixture, the four attempt-1 modules with their `git show attempt-1:<path>` sources and where each lands, the schema dump, the two tracks ⟨D29⟩ ⟨D38⟩ ⟨D40⟩.
- §15: `%Turnstile.Config{}` fields with type, default, and the decision that adds each; `adapter_options` keys per adapter ⟨D45⟩.

Dropped: adoption steps, tags, the transaction-id reader, compile-time binding, capability declarations in adapter packages, OSCAL and 20x output, the event-store ledger mode as a mode, `--diff`, the "if ordering defeats the wrap" sentence, the measured-latency column of the comparison table.

## Gate

```
$ grep -niE "\b(simply|just|obviously|easy|easily|of course|basically|note that|in order to)\b|!|—" docs/reference.md ; echo "exit=$?"
exit=1
$ grep -niE "visibility-safe|compile_env|bound at compile time|xmin|event-store mode|v10a|adoption step" docs/reference.md
$ grep -nE "provider\b" docs/reference.md | grep -viE "cloud service provider|identity provider|the provider's|declared by the provider|provider-chosen|provider imports|provider who"
```

Two inequality operators, written with the exclamation character in the first draft, tripped the first grep and were reworded.

## Citation check

Every `docs/reference.md §n` in `PLAN.md`:

| PLAN.md line | Citation | Section title | Claim | Satisfied |
|---|---|---|---|---|
| 25 | §12 | Pinned sources, toolchain, generator inputs, statement files, glossary | bumping a pin outputs the lint's diff of affected scenarios | yes (Bump procedure) |
| 41 | §7 | Audit records: shapes, span, caps, sizes, shape tests | record shapes and caps | yes |
| 47 | §5 | Policy-version events | only the rare policy event holds bytes | yes |
| 62 | §9 to §10 | Ledger positions; Ledger modes | mode claims, positions, and the reader | yes |
| 72 | §6 | The Repo seam | a Tier 1 sweep generated from the module re-proves the classification at runtime | yes (Proof at runtime) |
| 72 | §8 | Bulk writes and fact fields | a million-row sync that changes nine facts records nine | yes (sentence added) |
| 76 | §7 | Audit records | sizes, caps, and shape tests | yes |
| 87 | §13 | The OpenFGA adapter | the graph adapter's design note | yes |
| 89 | §4 | Adapters: comparison, declarations, notes, latency | comparison and notes | yes |
| 118 | §2 to §3 | Dissemination controls and the portion; Rules and mechanisms | full tables | yes |
| 124 | §1 | Requirement groups, controls, and scenario ids | ids | yes (id-prefix column) |

## For the next agent

The writer of `docs/testing.md` and `docs/code.md`. The reference presumes these details and names them without designing them:

- **Per-test counter row** (§9): the sandbox `setup` inserts a `turnstile_ledger_counter` row named `test-<id>` inside the sandbox transaction and passes `ledger_counter:` through `Turnstile.Test.with_config/2`; committed tests use `default`. Testing owns the setup; code owns `Turnstile.Test.with_config/2` (process dictionary, `self()` then `$callers`).
- **Committed-repo cases** (`@tag :committed`, `async: false`, truncation through the owner-role repo): interleaved transactions and lock cost (§9), the append-only grant, reconcile against out-of-band writes, the three projection cases driving `drain_once/1` (§13), the revocation-latency case per adapter from a template in core (§4). The latency case uses `System.monotonic_time(:millisecond)` and `Turnstile.Test.poll/2`; its poll interval is written to `results.json` as the floor.
- **The formatter**: `Turnstile.Assess.Formatter`, run beside the default formatter, writes `results.json` with the fields in §12; the skip reason comes from the `scenario` macro's tag (`{:capability, :c3}` or `:needs_ledger`). CI fails on `executed` zero or an undeclared skip ⟨D33⟩.
- **The fake FGA client**: `Turnstile.Fga.Client.Fake`, an `Agent` per test started with `start_supervised` (the raising variant), holding stores, models, tuples; `write/3` rejects duplicates and missing deletes atomically; `check/3` and `list_objects/3` answer from present tuples without model evaluation; every return is the real type ⟨D34⟩. The behaviour's callbacks are listed in §13. Decision cases run against `openfga run --datastore-engine memory`, a store per test.
- **The config override pattern**: `%Turnstile.Config{}` (§15) validated once at boot by NimbleOptions; the adapter, ledger, counter name, owner repo, seam mode, and `adapter_options` all flow through `with_config/2`, which is how `AdapterCase` runs four adapters in one `mix test`.
- **Owner-role repo**: `Turnstile.TestRepos.Owner` is `use Turnstile.Repo, role: :owner` and is the `owner_repo` in test config; reconcile, genesis, the catalog check, and truncation go through it. The cluster's two roles are unchanged from v8 TESTING §3.
- **The `Turnstile.Schema` macro** (§6, §8): `object_type/1`, `carries/1`, `fact/2` (per column: `kind:`, `subject:`, `object:`, `element:`), `relationship/1` (per row: `subject:`, `object:`, `attributes:`). Code decides its implementation; the reference fixes the declaration surface.
- **Shape tests** count queries from `[:repo, :query]` telemetry with transaction-control statements filtered; the table in §7 is per adapter and per ledger mode; the `set_config` statement counts as one query for Postgres.
- **Ported modules** (§14): `scenario.ex`, `language_lint.ex`, `case.ex`, `provider_case.ex` from `attempt-1:apps/turnstile_core/lib/turnstile/conformance/`; `provider_case` becomes `AdapterCase`, `axis` becomes `control:` plus group, and the `scenario` macro validates `control:` at expansion and writes the formatter's skip reason.
- **Thin-app CI order** (§12): migrate, `pg_dump --schema-only` into `priv/schema/<adapter>.sql` and diff, Tier 2 with the formatter, `mix turnstile.assess`, `git diff --exit-code` on `statement/statement.md`; `example_code` runs the Tier 2 step twice, once per ledger mode ⟨D44⟩.
- **Structs the reference names** that code must define: `%Turnstile.Decision{head_position, applied_position, ...}` (two positions, not v8 CODE's one), `%Turnstile.FactEvent{}`, `%Turnstile.PolicyVersion{}`, `%Turnstile.Exemption{}` (with `kind: :declared | :library`), `%Turnstile.Subject{kind:}`, `Turnstile.Error.Unmediated`, `Turnstile.Error.Engine`, the `Turnstile.Capabilities` behaviour (`capability/1`), `Turnstile.Projection` (`checkpoint/1`, `drain_once/1`, `rebuild/1`, `reconcile/1`), `Turnstile.Fga.Client`, `Turnstile.Fga.TupleMapping`, `Turnstile.Ledger.Dialect` with seven questions.
- v8 TESTING §5's row "positions consumed in a rolled-back sandbox transaction are gaps" is no longer true: positions come from the counter row and roll back with the transaction (§9).

## Open

1. **`Example.User`'s protection.** ⟨D10⟩ lists Document, Portion, Program, Assignment, OfficeRole, and Marking as protected and Category and Country as lookup tables; User is in neither list. The reference treats it as an unprotected fact schema (§8: facts recorded, no decision needed) because ⟨D10⟩ says protection is iff an object type is declared. If User should be protected, §8's example gains `object_type :user` and §3a gains a read scenario for it.
2. **`read_redacted` as a second Document operation.** ⟨D5⟩ says "a Document decision plus a Portion `scope`" without naming the Document operation. A Document decision under C2 over the banner would deny every redacted read the banner blocks, so §2 defines `read_redacted` as C1 alone at document level with C2 tested per portion. Nearest faithful reading; the FGA model's `can_read_redacted` follows it.
3. **The counter take on `Dialect.Postgres`.** ⟨D6⟩ says "take by `SELECT ... FOR UPDATE`, advance by the number of events". §9 and §11 let the Postgres dialect collapse the two into one `UPDATE ... RETURNING` and give `Dialect.Generic` the literal sequence. The single-row fact write count in §7 is therefore "the re-read, the write, one ledger insert, and the counter take", one statement more than the brief's phrase.
4. **Names chosen here, not by a decision:** the macro module `Turnstile.Schema` and its `fact/2` and `relationship/1`; the component atoms in the capability record (`:adapter | :seam | :database | :engine | :application`); the `declared_cascades` config field (⟨D21⟩ needs the declaration to live somewhere and ⟨D45⟩'s list omits it); the `results.json` field names; the scenario id scheme; the `Turnstile.Fga.Client` callback list; `Turnstile.PolicyVersion`; `Turnstile.Error.Engine`.
5. **The sixty scenarios in §3a are a draft for S1 to freeze** ⟨D30⟩ ⟨D46⟩. Enhancement membership carries §1's ⟨verify⟩; the PS-4 parameter compared in §4 is ⟨verify⟩; `aud-08` (rolled-back write leaves no fact event) and `rev-07` may belong to Tier 1 instead.
6. **FGA model additions to verify at S10:** the `portion` type and `from portion` on the document's flags mean the banner is derived on FGA while the domain also writes `Document.marking` as the union; the tuple mapping writes both, harmlessly, and reconcile must expect the union. Whether a condition on a tuple-to-userset (`category with before_decontrol`) compiles as written, and whether FGA keys a tuple on its condition context (the decontrol read-diff-write), are both ⟨verify⟩ in §13.
7. **Inherited from the previous handoff:** the Darwin Cerbos binary is unsigned and may need `xattr -d com.apple.quarantine` or an S0 note; `Example.Repo`'s placement (library app or thin app) is unstated in the reference, which says only that the thin app starts the projector and the reconcile scheduler.
8. **§14 still points at `docs/testing.md` for the cluster's mechanics**, which does not exist yet; the summary there is v8 TESTING §2 to §7 with the counter row, the owner-role repo, and the fake client applied.
