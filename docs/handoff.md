# Handoff
*Mode: Reference. Written from scratch by the agent that wrote plan v9; the next agent overwrites this file.*

## Task
Write `PLAN.md` at the repository root: version 9 of the Turnstile plan, a revision of `plan/v8/PLAN.md` that applies every decision in `docs/decisions.md` (D1 to D46; D47 to D49 are process and stay out of the plan). Keep v8's voice, section order, and every sentence still true. Cite `docs/reference.md §n` with v8's section numbers. Then write this file and commit.

## Done
- `PLAN.md`: 243 lines against v8's 216. Section order unchanged: intro, Who it is for, Words, The question, Decisions, Facts, The ledger, The seam, Audit, Adapters, The line, The example, Evidence, Adoption, Packages and conventions, Phases, Decisions list, Deferred. Every em dash in v8 was rewritten as a comma, colon, parenthesis, or new sentence, since the gate forbids the character. The three ⟨open n⟩ marks are gone; the one ⟨verify⟩ (the FedRAMP-assigned PS-4 value) stays. Forty-two of the forty-six decisions are cited inline as ⟨D<n>⟩; the four that are not are explained in the table below.
- New paragraphs, all from the decisions: positions from the counter row (§The ledger); matching rules and exemptions (§The seam); object types and the fact mapping of the CUI domain (§The example); the formatter, the two statement files, and the skipped-scenario failure (§Evidence); the migration rule and the schema dump (§Packages); the stages as a list (§Phases); fourteen new bullets in the decisions list; the five deferred lines.
- Removed: the adoption table and its tag paragraph, replaced by one paragraph under the same heading; the event-store mode bullet; the OSCAL, 20x, and `--diff` sentences; "visibility-safe reader"; "the adapter bound at compile time"; "type checker at the strictest setting"; `docs/adr/` and `docs/how-to/` from the tree; the `OPENFGA.md`, `REFERENCE.md`, `TESTING.md`, `CODE.md` file names, now `docs/reference.md §n`, `docs/testing.md`, `docs/code.md`.
- Absorbed from files with no v9 counterpart (D43): `OPENFGA.md` §7's three amendments as a decisions-list bullet; `COMPANION.md` §14's roads not taken folded into the bullets they belong to (hosted engines, compile-time mediation, event-sourcing the application, the filter language, "provider").
- `docs/handoff.md`: this file.
- Nothing under `plan/` or in `docs/decisions.md` was modified.

## Gate
Run from the repo root. The first command is the banned-word grep from the task brief: a case-insensitive search of `PLAN.md` for the nine banned words, the exclamation mark, and the em dash, followed by `echo "exit=$?"`; it cannot be quoted here without failing D43's grep over `docs/`. The other three commands are:

```
grep -n "⟨open" PLAN.md
grep -niE "visibility-safe|compile-time binding|bound at compile time|provider\b" PLAN.md | grep -vi "cloud service provider\|identity provider\|the provider's\|declared by the provider\|provider-chosen\|provider imports"
grep -n "v0-\|v10a\|adoption table\|tag by tag" PLAN.md
```

Output, in order, after the last edit:

```
exit=1
```

The other three commands printed nothing.

## Decision coverage

| Decision | Where PLAN.md reflects it |
|---|---|
| D1 | Reflected by absence: no migration-from-the-old-tree paragraph. §Packages names the `attempt-1` branch as the source of ported files (with D40). Not cited inline, since no paragraph rests on it. |
| D2 | Intro; §Adapters (one library app bound four times); §The example (last paragraph); §Evidence (Tier 2 once per thin application); §Packages tree; §Decisions list. |
| D3 | §Adoption (one paragraph); §Phases (S5 gone); §Decisions list; §Deferred. |
| D4 | §Words (adapter, never provider); §Evidence (`mix turnstile.assess`); §Packages (twelve apps, prefix rule); §Decisions list. |
| D5 | §The example (schema block without ⟨open 1⟩, the portion paragraph); §Adapters (Postgres line, second policy); §Decisions list. |
| D6 | §The ledger (counter-row paragraph, the named row for tests); §Decisions list. |
| D7 | §Adapters (admission paragraph: domain-free declaration, capability per rule in the thin app); §Packages (engineering: bound at boot); §Decisions list. |
| D8 | §Packages engineering sentence (versions, `nixos-unstable`, Cerbos from its archive); §Decisions list. |
| D9 | §Who it is for (item 8); §Words (20x docs read by the lint); §The ledger (two modes); §The line (second altitude test deferred); §Evidence (one profile); §Decisions list; §Deferred. |
| D10 | §The seam (refusal wording, the matching paragraph); §The example (which schemas declare object types); §Decisions list. |
| D11 | §The seam (exemptions paragraph); §Decisions list. |
| D12 | §Facts (the macro, old and new); §The example (the domain's mapping); §Decisions list. |
| D13 | §The ledger (no xmin reader; watermark reader as a later dialect option). |
| D14 | §Adapters (revocation latency as evidence, components, "not measured", compared never asserted); §Decisions list. |
| D15 | §The seam (`around_query/3`, the owner-role repo); §The line (the second Repo); §Decisions list. |
| D16 | §Evidence (formatter, `results.json`, `statement.md`, `evidence.json`); §Packages tree; §Decisions list. |
| D17 | Closed by D7; §Packages engineering sentence. Not cited inline, D7 is. |
| D18 | §Decisions (head read is one query, `nil` in mode none); §Adapters and §The line (reworded "database-free", the boundary rule's list); §Evidence (shape counts per adapter and mode); §Decisions list. |
| D19 | §The seam (after-compile check, overrides asserted in force); §Decisions list. |
| D20 | §The seam (locked re-read, upsert refusal); §Decisions list. |
| D21 | §The ledger (Ecto ledger bullet, the catalog check); §Decisions list. |
| D22 | §The ledger (the head is the committed counter value; replay exact to the head). |
| D23 | §Adapters (OpenFGA line); §Evidence (projection cases on the committed repo). |
| D24 | §The ledger (projector: checkpoint per acknowledged write, drain by diff); §Decisions list. |
| D25 | §The ledger (rebuild into a fresh store, the swap printed); §Decisions list. |
| D26 | §Decisions (RLS decision record: rule `true`, migration number, settings hash); §Adapters (Postgres line: `check` for writes, the per-rule table); §Decisions list. |
| D27 | §Adapters (Cerbos line); §Decisions list. |
| D28 | §Deferred (component definition, never a whole SSP). PLAN.md nowhere says "SSP validated against FedRAMP's templates". |
| D29 | §Adapters (admission paragraph); §Packages tree (each adapter line); §Decisions list. |
| D30 | §Adapters (Postgres write gates as a note; capability levels with the component named); §Evidence (the scenario table; POA&M rows only for unsupported); §Decisions list. |
| D31 | §Packages engineering sentence ("every type warning an error"). |
| D32 | §The question (subject kinds; `scope` under a denied precondition); §The seam (refusal raises, audit mode returns the unscoped result); §Decisions list. The process-dictionary, `NOBYPASSRLS`, and boot-time policy-version lines are companions only. |
| D33 | §Evidence (the executed-count paragraph); §Decisions list. |
| D34 | §Packages testing sentence. |
| D35 | Companions only (`docs/code.md` §6). |
| D36 | §The question (`explain` answered unsupported at runtime); §Decisions list. |
| D37 | §Adapters (OpenFGA line: client behaviour and fake); §Decisions list (against the outbox). |
| D38 | §Packages (schema dump per thin-app job). |
| D39 | §Packages documentation sentence (`docs/glossary-index.md`, translation tables). |
| D40 | §Packages (ported conformance mechanisms); §Phases S1; §Decisions list. |
| D41 | §Packages documentation sentence; §Decisions list. |
| D42 | §Deferred, not deleted. |
| D43 | §Packages tree (root files, `docs/`, `plan/`) and the documentation sentence. |
| D44 | §Packages tree, the twelve-app sentence, the migration rule, the second `example_code` job. |
| D45 | §Packages engineering sentence (the struct, NimbleOptions, the only runtime configuration); its fields appear where they are used: the counter name (§The ledger), declared exemptions and the owner repo (§The seam). |
| D46 | §Phases. |

## For the next agent
The companions writer. PLAN.md cites these `docs/reference.md` sections by v8 number and expects each to exist with the content named:

- §1: scenario groups and ids (unchanged).
- §2 to §3: dissemination controls and the rules; C4 reworded per D5; the "where the adapters differ" paragraph without the Cerbos "or" (D27) and pointing at the thin apps' per-rule tables (D26); the Tier 2 scenario table as a new section beside §3 (D30).
- §4: the comparison table and the adapter notes, with the declaration paragraph split (D7), the Postgres note carrying `around_query`, `check` for writes, the portion policy, `NOBYPASSRLS`, and "not measured unless a replica is configured" (D14, D15, D26, D32), the Cerbos attribute declaration shape (D27), and the OpenFGA note rewritten for D24 and D25.
- §5: the `:policy_version` kind's payload (D12).
- §6: the seam, with the Matching paragraph and the `object_type/1` and `carries/1` declarations (D10), `%Turnstile.Exemption{}` (D11), four extension points (D15), the after-compile rewrite (D19), the write bucket naming upserts (D20), and the sentence "audit mode returns the unscoped result" in those words (D32).
- §7: record shapes and caps, the RLS `scope` variant (D26), and the shape table with one row per adapter and ledger mode (D18); the single-row fact write count "the re-read, the write, one ledger insert" (D20).
- §8: the bulk API, the fact-mapping macro (D12), the locked re-read and the upsert refusal (D20).
- §9 to §10: the counter table and the head read (D6); the modes table without the event-store row, kept as a note (D9); the Ecto-ledger claim with declared cascades (D21) and "replay exact after reconcile" for out-of-band drift only (D22).
- §11: the reader-strategy row as "counter row; a watermark reader is a later dialect option" and the cascade-query row (D6, D21).
- §12: pinned sources, the `results.json` schema, and the statement file layout (D16); the assessment glossary, which also holds COMPANION Appendix A's terms until package glossaries exist (D43). The bump procedure is cited from PLAN §Words as "a procedure whose output is the lint's diff"; v8 §12 points at `docs/how-to/bump-sources.md`, which D43 drops, so §12 should say the how-to lives in `turnstile_assess` once S2c writes it.
- §13: PLAN.md calls this "the graph adapter's design note", which v8's four-line §13 is not; OPENFGA.md §1 to §5 are absorbed here with D23 to D25 applied, plus the client behaviour and its fake (D37), the `@tag :committed` on the projection cases (D23), and the declaration summary reduced to the domain-free facts, the per-rule part moving to `example_fga` (D7).
- `docs/testing.md` and `docs/code.md` are cited by name only, from §Packages.

Wording in PLAN.md that presumes a companion detail v8 does not have yet:
- "The row is named in the configuration, so a test can take its own and async tests never contend" (§The ledger): the per-test counter row of D6's sandbox consequence, which needs a `docs/testing.md` §3 or §5 paragraph and the `ledger_counter` field in `docs/code.md` §2.
- "The thin app's per-rule table names the mechanism for each of C1 to C13" (§Adapters): the table itself is `example_postgres`'s; `docs/reference.md` §3 only points at it.
- "CI fails on a count of zero, or on a skip that names no declared capability, or, in a mode-none run, no need for a ledger" (§Evidence): `docs/testing.md` §6's D33 paragraph and the formatter's counts.
- "`example_code` runs Tier 2 twice, once per ledger mode" (§Packages): `docs/testing.md` §7.
- "Every fake returns a value of the real type rather than raising" (§Packages): `docs/code.md` §4's Fakes rule (D34) and the capability-record and list-literal rows in §6 (D35).
- "The lint that reads test files without compiling them" (§Packages): `docs/testing.md` §6 names the ported macro and AST reader (D40).
- The stage list in §Phases names decisions per stage in prose only; `docs/delivery.md` is where each gate becomes a command and its expected output (D46).
- The `Decision` struct in v8 CODE §2 has one `position` field; PLAN §Decisions carries two (head and applied), as the previous handoff already noted.

Calls I made, not the owner's:
- The title is `Turnstile: plan, v9`. The brief spelled it with an em dash, which the gate's first command forbids anywhere in the file; a colon is the nearest reading.
- §Adoption survives as a heading over one paragraph, as the brief asked, rather than being removed outright as D3's consequence line says; the paragraph says the guide is deferred and where its material comes from.
- The mode line keeps v8's sentence about tables moving into package docs as the packages appear.
- The decisions list gained fourteen bullets, one per new choice, and kept every v8 bullet whose choice survives; bullets whose choice changed were rewritten in place rather than deleted, so a v8 reader finds them where they were.

## Open
- The title line: the brief's wording carries an em dash and the gate forbids it; I used a colon. If the owner wants the dash in the title, the first gate command needs an exception for line one.
- §Adoption as one paragraph under the v8 heading versus D3's "remove §Adoption entirely": the brief asked for the paragraph, so the heading stays; either reading is a one-line change.
- The ⟨verify⟩ on the FedRAMP-assigned PS-4 value stays, since no decision resolved it.
- Inherited from the previous handoff and still open: whether the per-test named counter row (D6) is acceptable to the owner; whether mode none needs the second `example_code` Tier 2 job (D44); where COMPANION Appendix A's terms live before package glossaries exist; whether the Darwin arm64 Cerbos tarball runs unsigned on macOS.
- `Example.Repo` and the web layer are placed in the library app `turnstile_example` (D44); PLAN §Packages says so. If the S1 agent cannot make that compile with per-thin-app `config_path`, the alternative (each thin app owns its Repo and the contexts take a repo parameter) changes the tree in §Packages and the last paragraph of §The example.
