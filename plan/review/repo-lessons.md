# How the first Turnstile should inform plan v8
*Mode: Reference. Produced 2026-09-07 by a review agent reading the existing repo (root `PLAN.md`, `CLAUDE.md`, `docs/`, `apps/*`, the deleted decision records via `git show fac7683:docs/adr/…`) against `new-plan/`. Paths are relative to the repo root unless prefixed `new-plan/`.*

## A. Hard-won lessons in the repo that v8 does not yet reflect

For each: what the repo learned, where it is written, and whether v8 has an equivalent, dropped it deliberately, or lost it silently.

### A1. Naming audit — words with multiple meanings, names that read blank

Repo finding: `docs/status.md:97-126` lists seven words carrying more than one meaning ("context", "term", "record", "grant", "matrix", "vocabulary", `Turnstile.System`/`:system`) and a list of names that read blank to a newcomer (`seam`, `fact`, `capability` with `:native/:limited/:unsupported`, `Terms`, `Opts`, `with_actor`, `scope` beside `filter`, the axis atoms). `docs/semantics.md` classifies each departure from the field's vocabulary as principled, drift, or unrecorded.

v8 status: **partly adopted, partly silently lost.**
- Adopted: 800-162 subject/object/operation/environment (`new-plan/PLAN.md:27`), "adapter" reserved and "provider" rejected (`COMPANION.md:346`), "no abbreviations in public names" (`CODE.md:111`), banned-words lint enforcing the two reserved words (`PLAN.md:174`).
- Still carried without a decision: "scope" (semantics.md flagged the collision with Cerbos scoped policies and OAuth scope, `docs/semantics.md:449, 573-575`), "seam" (`PLAN.md:65-67`), "capability" with the same three levels (`REFERENCE.md:67`; the repo's audit called these blank at `status.md:115-117`), and "projection" now in a third sense (repo: capability axis `:projection` for redacted reads, `semantics.md:485`; v8: ledger-to-engine projection, `PLAN.md:53`). The "context" overload (bounded context / Phoenix context / request facts) is worse in v8 because `environment` sits beside `context` in the same docs.
- The audit method itself (list homonyms, classify departures, one place they live) is not in v8's documentation section (`PLAN.md:174`). Worth carrying as a working rule.

### A2. Type-safety findings — where the seam forced a weaker type

Repo findings, in `docs/type-safety.md` and the code:
- Core had no Ecto, so `queryable_type!/2` matches a map shape `%{from: %{source: {_table, schema}}}` (`apps/turnstile_core/lib/turnstile/vocabulary/vocabulary.ex:51-55`) and `scope/4` returns `term()`. v8 reverses this deliberately: Ecto in core and `scope` as a `dynamic` (`PLAN.md:33, 195`; `COMPANION.md:91, 336`). Deliberate, and correct.
- `Turnstile.Error.reason` is `:forbidden | :not_found | :unsupported | atom()` (`apps/turnstile_core/lib/turnstile/port/error.ex:12`), an open set the checker cannot narrow. v8 uses exception structs per outcome (`CODE.md:93`). Deliberate improvement.
- The Stub `scope/4` lesson: a stub that raised was typed as returning no value, making every scope call site a certain crash under `warnings_as_errors`; the fix was an `Unscoped` struct (`apps/turnstile_core/lib/turnstile/provider/stub.ex:6-9`; ADR-0034 via `git show fac7683:docs/adr/0034-stub-build.md`). v8's fake adapter (`PLAN.md:178`, `TESTING.md:56`) has no stated rule that a fake must return a value of the real type. **Silently lost.** It will recur the first time someone writes `def scope(...), do: raise "not implemented"` in `turnstile_fga` during Phase 3.
- `Turnstile.Terms.capability/1` is generated as one clause per record plus a fallback, instead of a map lookup, because the checker read the empty-map lookup as returning only the default (`apps/turnstile_core/lib/turnstile/vocabulary/terms.ex:73-74`). v8's "capability per scenario" declaration (`REFERENCE.md:67`) does not say how it is represented. **Silently lost**; small, but it is exactly the class of thing `CODE.md` enumerates.
- `RoleDefinition.actions` typed `[atom()]` because the checker cannot narrow a list literal from params (`status.md:183-184`). Not in v8; belongs in `CODE.md` as a known limit.

### A3. Compile-time binding — `who_can` decided at expansion

Repo: `use Turnstile, provider:` is bound at compile time (ADR-0003 rejected runtime config because "generated functions cannot be checked against a provider"); the consequence is `who_can/3` is generated or omitted at vocabulary expansion via `Turnstile.supports?/2` (`apps/turnstile_core/lib/turnstile.ex:347-385`), so a provider gaining `who_can` requires recompiling the vocabulary (`status.md:181-183`), and CI needs a build per provider (`MIX_BUILD_ROOT`, ADR-0031).

v8: keeps compile-time binding through `Application.compile_env/3` (`CODE.md:57`) and makes `explain` optional per adapter (`PLAN.md:33`, `@optional_callbacks` at `CODE.md:91`). Same shape, same consequence, not stated: an application compiled against `turnstile_postgres` has or lacks `explain` at expansion, and swapping adapters means a rebuild per adapter in CI. **Silently lost.** v8 should say either "one build per adapter, and here is the CI matrix" or "optional answers return `{:error, %Unsupported{}}` at runtime rather than being absent". The repo chose the former and paid for it in `apps/turnstile_example/mix.exs:15-25`.

### A4. The "no context body has ever executed" trap and phase ordering

Repo: after Phase 1, 64 scenarios existed and all were skipped under the stub build (`status.md:60-62`); the stub's `terms.ex` lists all 64 by hand as `:unsupported` (`apps/turnstile_example/providers/stub/terms.ex`), and a scenario added without a line there compiles as `:native` and fails under the stub, so "the stub build in CI is the check" (ADR-0034). Net: every context function in the example was written and never run.

v8: Phase 1 is the fake adapter plus in-memory ledger plus Tier 1 on real Postgres, and Phase 2 builds the example tag by tag with statements regenerated in CI (`PLAN.md:178-180`, `TESTING.md:82`). This ordering avoids the trap in practice. But v8 never names the trap, and nothing in `TESTING.md` forbids a green suite made entirely of skipped scenarios. **Silently lost as a rule.** A one-line invariant belongs in `TESTING.md`: a Tier 2 run reports the count of executed scenarios per adapter, and CI fails if it is zero, or if any scenario is skipped without a declared `:unsupported` capability.

### A5. The rebac/openfga split and the in-memory fake as reference adapter

Repo: `turnstile_rebac` is engine-neutral with a `Client` behaviour; "An in-memory fake client in test support is the reference implementation and the first thing built" (`apps/turnstile_rebac/PLAN.md:21-22`; ADR-0006; `docs/context-map.md:36-37`); `turnstile_openfga` is a thin adapter over it.

v8: `turnstile_fga` talks to a real server with `openfga run --datastore-engine memory` (`TESTING.md:71`, `OPENFGA.md:159`); no engine-neutral layer, no fake client. Was this deliberate? v7 dropped OpenFGA on boundary cost (`archive/PLAN-v7.md:79, 184`); v8 restored it (`COMPANION.md:328`) without revisiting the split. **Deliberately simplified, but the reason is not recorded.** Does v8 need a fake client? Two arguments say yes:
- Tier 1 is supposed to run against every adapter with the fake adapter as the reference; for FGA the "adapter" includes the projector, drain, reconcile, and positions (`REFERENCE.md:144, 180`), and those are the parts most worth testing without a server. An `Agent`-backed tuple store behind a `Turnstile.FGA.Client` behaviour lets the projector's convergence and drift cases (`REFERENCE.md:180`) run in the same `Agent` style TESTING.md:56 already uses.
- The bigger reversal: ADR-0029 rejected application-owned facts with an outbox because "no mechanism makes a dual write atomic" and it "rebuilds the engine's consistency machinery outside the engine". v8's `turnstile_fga` is precisely ledger-as-outbox (`OPENFGA.md:23`) with non-idempotent tuple writes (`OPENFGA.md:139`). v8 may be right (the ledger is the system of record for assessment, so the outbox has a second justification), but the decision record should cite ADR-0029 and answer it: duplicate-write handling on re-drain, and what a 3PAO sees when the ledger and the engine disagree.

### A6. Migration as teaching artifact, pg_dump checked against priv/schema

Repo: one migration per chapter in the example, "CI dumps each end state into `priv/schema/` and fails on drift" (ADR-0030; `apps/turnstile_example/docs/providers/rbac.md:58-62`; root `PLAN.md:57`). Providers ship at most a helper a migration may call plus a generator (`CLAUDE.md:12`).

v8: adoption tags v0…v10c with CI regenerating each tag's statement and diffing (`PLAN.md:132-142, 146`; `TESTING.md:82`). **Deliberately replaced**, and the replacement is better as evidence. What did not survive: the schema dump check. The tags prove the assessment statement is stable; nothing proves the example's schema at each tag matches what the docs show. Cheap to add back as one CI step per tag.

### A7. Capability matrix per scenario per provider, and the `Terms` mechanism

Repo: `Turnstile.Terms` holds `term/2` (a translation pair between the domain's word and the provider's) and `capability/3` per scenario (`apps/turnstile_core/lib/turnstile/vocabulary/terms.ex`); `Turnstile.Conformance.Matrix` renders scenario × provider plus the four ownership rows (`apps/turnstile_core/lib/turnstile/conformance/matrix.ex`, `lib/mix/tasks/turnstile.matrix.ex`). ADR-0031 rejected putting capability records in the provider package because "a provider naming `share_with_outsider` is the leak the glossaries exist to prevent", and rejected tags on scenarios; the records live in `apps/turnstile_example/providers/<name>/terms.ex`.

v8: adapters declare "capability per scenario" in their own package (`REFERENCE.md:67`, `PLAN.md:85`, and the FGA summary at `REFERENCE.md:180` lists "C3, C4, C9 native; C8 adapter-side"). This is the placement ADR-0031 rejected: `turnstile_fga` now knows the ids of CUI scenarios that live in the example. **Reversed without citing the rejection.** The v8 argument for it (the adapter's declaration is part of its admission, `PLAN.md:85`) is reasonable, but the leak should be named and accepted, or the records should move to the example's per-adapter directory as before. The `term/2` word map has no v8 equivalent; the closest is "per-adapter notes" (`PLAN.md:169`). The ownership rows are replaced by the origination/responsibility split (`PLAN.md:122`; `COMPANION.md:268`; `archive/PLAN-v6-proposed-changes.md:16-34`), which is a deliberate and better framing. The matrix renderer is replaced by "four statements side by side in the README" (`PLAN.md:83`), which is hand-written rather than generated.

### A8. Conformance `scenario/3` macro and citation lint

Repo: `scenario/3` requires `rule:` and an `axis:` from a fixed list, reads the capability at expansion, and tags the test `skip:` with the terms module and note when `:unsupported` (`apps/turnstile_core/lib/turnstile/conformance/case.ex:68-105`). `Scenario.read/1` parses the test files as AST without compiling (`conformance/scenario.ex`); `LanguageLint` checks that every rule cited exists in the glossary and every term in the glossary is a bold first cell (`conformance/language_lint.ex`).

v8: scenario sentences citing a control id, checked against pinned sources (`PLAN.md:118`; `REFERENCE.md:172-176`); tiers (`PLAN.md:120`). Stronger citation target, same mechanism. Not present in v8: the "skip carries the adapter's own note" behaviour (which is what makes a skipped scenario readable in a report), the AST reader that lets a lint run without compiling the suite, and the `unknown_scenarios/2` check that a doc table cannot name a scenario that does not exist. **Equivalent in intent; mechanism details silently lost.** The `Case` and `Scenario` modules are the two most portable files in the repo (see C).

## B. Where v8 improved, so the old choices are not carried forward

- The Repo seam answers the repo's own open problem: "Nothing proves a context function calls authorization at all" (root `PLAN.md:180`); v8 `PLAN.md:65-71`.
- `scope` as an Ecto `dynamic` that can only narrow, versus the repo's untyped queryable that the Stub had to return unchanged (fail-open was one of the rejected options in ADR-0034).
- Exception structs for outcomes (`CODE.md:93`) versus the open `atom()` reason and the per-vocabulary `reasons:` list (`error.ex:12`; `apps/turnstile_example/lib/example/authz.ex`).
- Ledger with four 800-162 fact kinds and replay, versus `Turnstile.Fact` with application-chosen kind atoms (`:role`, `:definition`, `:read_in` ...) that the audit called blank.
- A clock behaviour (`COMPANION.md:169`); the repo passed `mfa_at` in `opts[:context]` and had no clock.
- Privileged users as separate accounts (`PLAN.md:35`) versus the `:system`/`:operator` atoms and the `with_actor`/`as_system` drift the repo never resolved (`status.md`; ADR-0016 vs `port/provider.ex`).
- Scenarios keyed to external control ids rather than to the example's own R1–R13 rules.
- Tier 1 on real Postgres from Phase 1, versus the repo's stub-only Phase 1.
- Fail-closed classification of every Repo surface (`REFERENCE.md:93`), which the repo's `Turnstile.Web.Plug` approximated only at the controller edge.

## C. Reusable assets

Portable with modest change:

- `apps/turnstile_core/lib/turnstile/conformance/scenario.ex` — AST reader for scenarios; change the matched form and the required keys (`control:` instead of `rule:`). Keep.
- `apps/turnstile_core/lib/turnstile/conformance/language_lint.ex` — glossary-term and rule-id lint; retarget rule ids to control ids from the pinned sources; `unknown_scenarios/2` carries over as is. Keep.
- `apps/turnstile_core/lib/turnstile/conformance/case.ex` — `scenario/3` with compile-time validation and skip-with-note; rename `vocabulary:`→ adapter/declaration, drop `who_can` asserts, keep `assert_scope_matches_can`-style cross-answer checks. Keep the shape.
- `apps/turnstile_core/lib/turnstile/conformance/provider_case.ex` — the property suite with `actors/0`, `pairs/0`, `grants/0`, the both-or-neither `queries/0`+`all/1` check in `__before_compile__` (lines 138-146), and the refusal-shape assertion; this is the seed of `Turnstile.Conformance.AdapterCase` and `Gen`. Keep, rename throughout.
- `apps/turnstile_core/lib/turnstile/conformance/matrix.ex` and `apps/turnstile_core/lib/mix/tasks/turnstile.matrix.ex` — only if v8 wants the README's four statements generated rather than hand-written; the `Module.safe_concat` "not compiled" placeholder (lines 115-121) is the useful trick. Optional.
- `apps/turnstile_core/lib/turnstile/web/plug.ex` and `web/controller.ex` — compile-time check that an action belongs to the resource, refusal of command-typed actions at the controller (`controller.ex:126-133`), 404-vs-403 policy. Keep the ideas; rewrite over the v8 port.
- `umbrella.exs` — `compilers: [:boundary]`, `warnings_as_errors`, the `test` alias that compiles with warnings as errors first. Keep verbatim.
- `.credo.exs` lines 124-129 — Specs excluding test, UnsafeToAtom, MapGetUnsafePass. Keep; add v8's custom checks. Also fix the `strict: false` versus CI `--strict` mismatch.
- `docs/writing.md`, `docs/context-map.md`, `docs/glossary-index.md` — the Diátaxis-mode-per-file rule, one glossary per context, the homonym index. Keep; re-derive the index for the new packages.
- `docs/semantics.md` and `docs/references.md` — the field-vocabulary comparison is the groundwork for v8's 800-162 alignment; keep as a reference document.
- `apps/turnstile_example/PLAN.md:46-57` — the "why OrgRole is a table and not a token claim" argument (New Enemy Problem) is the same argument as v8's "no facts in tokens"; lift the paragraph.
- `apps/turnstile_example/test/support/fixtures.ex` — the builder/verb style (write through contexts as a privileged actor, `stepped_up/0` returning environment) survives a domain change.
- `.github/workflows/ci.yml` — skeleton only; replace setup-beam with a nix step and the env-var provider switch with a build matrix.
- `docs/status.md` working habits (the banned-word grep, the "thin spots" section) — carry as a CLAUDE.md rule.
- The deleted ADRs 0003, 0021, 0029, 0030, 0031, 0033, 0034 — reachable via `git show fac7683:docs/adr/<file>`; v8's `docs/adr/` (`PLAN.md:153`) should start from these, with v8's reversals recorded against them.

Throw away, because v8's vocabulary or design makes them wrong:

- `apps/turnstile_core/lib/turnstile.ex` — the vocabulary macro (provider/actor/resource/who_can, generated per-action functions with `reasons:`).
- `apps/turnstile_core/lib/turnstile/port/provider.ex`, `opts.ex`, `fact.ex` (kinds are app atoms, not 800-162 kinds), `error.ex` (atom reasons), `system.ex`, `ownership.ex`, `actor.ex`/`resource.ex` protocols (subject/object now), `provider/stub.ex` + `unscoped.ex` (keep the lesson, not the code), `vocabulary/terms.ex`, `vocabulary/aggregate.ex`, `vocabulary/vocabulary.ex`.
- All five provider apps (`apps/turnstile_rbac`, `turnstile_rebac`, `turnstile_openfga`, `turnstile_postgres`, `turnstile_cerbos`) — PLANs, glossaries, mix files; the Postgres `authz_dominates` and RLS-policy notes in `apps/turnstile_example/docs/providers/postgres.md` are the only content worth re-reading when writing `turnstile_postgres`.
- The example domain (org/project/document/portion/label with OLS-style dominance) — v8's example is CUI marking and the C1–C13 scenarios; `docs/glossary.md` R1–R13 and `permission-matrix.md` go with it.
- `providers/stub/terms.ex` (64 hand-listed lines — the trap itself).
- `docker-compose.yml`, `.tool-versions`, `config/config.exs` providers map, the `TURNSTILE_PROVIDER` env switch in `apps/turnstile_example/mix.exs`.
- Untracked junk: `erl_crash.dump` (5 MB) and `.elixir_ls/` at the repo root.

## D. Conflicts between the repo's rules and v8

| Repo rule | Where | v8 position | Where |
|---|---|---|---|
| "Providers own mechanism and decide where a grant fact is stored" | `CLAUDE.md:10`; ADR-0029 | Adapters; the ledger (application side) is the system of record and projects to the engine | `PLAN.md:27, 45-53`; `OPENFGA.md:23` |
| "Migrations exist only in `apps/turnstile_example`" | `CLAUDE.md:12`; ADR-0030 | `turnstile_ledger` and `turnstile_fga` need tables (ledger, positions, checkpoints) | `REFERENCE.md:144, 152-154`; `OPENFGA.md:157` |
| Packages core/rbac/rebac/openfga/postgres/cerbos/example | `umbrella.exs:9-16`; `docs/context-map.md` | core/code/postgres/cerbos/fga/ledger/assess/example | `PLAN.md:77-81, 153` |
| Docker Compose + `.tool-versions`; Nix rejected as a distraction for learners and because the OpenFGA server and Cerbos are not in nixpkgs | ADR-0021; `archive/PLAN-v6.md:366` | Nix flake is the only documented path; no Docker, no `.tool-versions` | `TESTING.md:17`; `archive/PLAN-v7.md:166, 200` |
| Erlang 29.0.6, Elixir 1.20.4-otp-29, verified 2026-09-03 | `.tool-versions` | Elixir 1.20 on OTP 28 pinned by the flake | `CODE.md:65`; `TESTING.md:12` |
| postgres:18.6, openfga v1.19.0, cerbos 0.55.0 | `docker-compose.yml` | postgresql 17 ⟨choose⟩, openfga ⟨verify nixpkgs⟩ | `TESTING.md:13` |
| ADRs deleted "for a fresh start" | commit `c036491` | Layout includes `docs/adr/`; "decision records only where a newcomer would reopen the decision" | `PLAN.md:153, 174` |
| Core has no Ecto; queryable matched by shape | `vocabulary.ex:51-55`; `type-safety.md` | Ecto in core; `scope` returns `dynamic` | `PLAN.md:33, 195` |
| Test names are scenario ids citing a rule id and an axis | `CLAUDE.md:14`; `case.ex:30-42` | Test names are scenario sentences citing a control id | `PLAN.md:118, 174` |
| Adapter chosen by `TURNSTILE_PROVIDER` env and `elixirc_paths` per provider dir | `apps/turnstile_example/mix.exs:15-25`; ADR-0031 | `Application.compile_env/3` | `CODE.md:57` |
| Reasons are atoms from a per-vocabulary fixed set | `error.ex:12`; `authz.ex` | Exception structs; no `{:error, :atom}` | `CODE.md:93` |
| `:system` / `:operator` atoms as actors; `Turnstile.System` struct | `apps/turnstile_example/lib/example/accounts/actor.ex:14`; `port/system.ex` | Privileged users are separate accounts | `PLAN.md:35` |
| Capability records live in the example's per-provider dir, never in the provider package | ADR-0031 | Adapter declares capability per scenario in its package | `REFERENCE.md:67, 180` |
| "Cross-context word use is a Credo check" | `language_lint.ex:17-18` | Banned-words lint enforces reserved words | `PLAN.md:174` — and the repo's Credo check never existed (`.credo.exs` has `requires: []`) |
| `warnings_as_errors: true`, `boundary` compiler | `CLAUDE.md:16`; `umbrella.exs` | Same | `CODE.md:18, 28` — no conflict |

## E. Recommendation

Start v8 in a fresh repository (or an orphan branch in this one) and port the assets in C, rather than rewriting in place. Every module under `apps/*/lib` carries the old vocabulary (provider, actor, resource, vocabulary, Terms, who_can, atom reasons), the package list, the env-var binding, the Docker/tool-versions environment, and the example domain all change, and `CLAUDE.md`, `PLAN.md`, `umbrella.exs`, and the CI workflow would each be rewritten from the first line; an in-place rewrite would be a delete-all commit followed by a new tree, which gives no continuity that `git show fac7683:docs/adr/...` does not already give. The value in this repo's history is the docs and the deleted ADRs, and v8's `docs/adr/` should open by re-recording 0003, 0021, 0029, 0030, 0031, 0034 with v8's reversals stated against them (Nix over Compose, ledger-as-outbox over provider-owned grants, adapter-declared capabilities over example-owned ones), so that the reasons the first attempt found are the first thing a newcomer reads rather than something recovered with `git show`.
