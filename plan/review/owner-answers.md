# Owner answers, 2026-09-07
*Mode: Reference. Decisions the owner made while working through the pre-implementation questions. Each entry feeds the v9 decisions file.*

## Q1. Repo reset
Orphan branch in this repo. Tag the current HEAD `attempt-1` first, then start an orphan branch with an empty tree, then commit `plan/` (v8 plus the review) as the first commit.

## Q2a. Adapter variants of the example
Base app as a library plus four thin apps. `turnstile_example` holds the CUI domain, the schemas, the contexts, and the scenario tests. `example_code`, `example_postgres`, `example_cerbos`, `example_fga` each depend on it and add only the adapter binding, migrations, policies or model, and config. Each thin app has its own CI job. Names of the thin apps are provisional until the names question is answered.

## Q2b. Adoption steps
Not kept. No `v0`…`v10` tags, no per-step statements, no tags CI job, no adoption table in the plan. The adoption path may return later as supplemental educational material after implementation. Consequences for v9: remove PLAN §Adoption table and the Phase 6 tag work; TESTING §7 loses the `tags` job; open decision 3 (statement format per tag) collapses to "one statement per thin app, regenerated on every PR".

## Q3. Names
"adapter" is the word; `Turnstile.Adapter` is the behaviour. Library packages keep the `turnstile_` prefix as v8 spells them: `turnstile_core`, `turnstile_ledger`, `turnstile_code`, `turnstile_postgres`, `turnstile_cerbos`, `turnstile_fga`, `turnstile_assess`, `turnstile_example`. The four thin example apps are `example_code`, `example_postgres`, `example_cerbos`, `example_fga`, the only packages without the prefix. The library name stays Turnstile.

## Q4. Portion marking
Model it. `Portion(marking: Marking)` under `Document`; a redacted read that returns the document with unreadable portions removed; `scope` works at portion level and C13 (scope equals check) must hold for portions too. Rule C4 (the banner rule) stays in the domain. Each adapter filters portions as their own rows with their own policy; for `turnstile_postgres` that is a second RLS policy on the portions table. Open decision 1 closes.

## Q5. Ledger positions
Counter row. Every fact-writing transaction locks one row in a library-owned table and takes the next position from it, so positions are commit-ordered with no gaps and the reader is "from position N". The serialization cost is measured and printed in the statement. Same on every database; the dialect seam stays so a Postgres watermark reader can be added later. REFERENCE §9 and §11 rewrite accordingly; the "visibility-safe reader" phrase goes away; Tier 1 keeps the interleaved-transactions case as the proof that no event is skipped.

## Process note
Every question's preamble goes inside the question text itself; message prose before the dialog is not seen by the owner.

## Q6. Adapter binding and capability declarations
Core reads the adapter from `%Turnstile.Config{}` at boot, so Tier 1 binds per test module and all four adapters run in one `mix test`. Each thin app fixes its adapter in config; `Application.compile_env/3` is reserved for the example's generated per-operation functions. Per-rule capability declarations (native / limited / unsupported per C-rule) live in `example_<adapter>`, not in the adapter package; adapter packages declare only domain-free facts (requires a ledger, scope capped, inventory item, origination defaults, parameters). This restores ADR-0031's placement; hole #7 closes.

## Q7. Toolchain
Pins as verified in `toolchain-pins.md` on 2026-09-07: lock `nixos-unstable`; `beam.packages.erlang_29.elixir_1_20` (OTP 29.0.6, Elixir 1.20.4); `postgresql_18` written explicitly (18.6); `openfga` from nixpkgs (1.19.0); Cerbos v0.55.0 from its release archive via a `fetchurl` derivation with hashes recorded per system (Linux x86_64, Linux arm64, Darwin arm64, Darwin x86_64); services-flake for `nix run .#services`. Nix is not installed on the development Mac (arm64); the S0 agent installs it, stopping to ask before running the installer because it needs an admin password and modifies the system (creates `/nix`, a launch daemon, build users). Docker stays uninvolved.

## Q8. Commits and orchestration
Sequential work, one branch (`main` on the orphan line), no worktrees. Each agent commits its own work when done, unsigned (`git -c commit.gpgsign=false`). A handoff document, `docs/handoff.md`, is written from scratch by every agent (never revised) and overwritten in the same commit; it is the channel from the agent to the orchestrator: what was done, gate command and its result, what the next task needs to know, open problems. The orchestrator reads only that file and the gate output to decide the next task.

## Q9. Review checkpoints
One pause, after plan v9 and its companions are written. The owner reads and approves or edits. After that the stages run to completion in sequence, each gated by the orchestrator, reporting at the end or when blocked.

## Q10. Scope of the first implementation
Trim. The generator emits one Rev 5 markdown statement per thin app: implementation status per control, responsibility split (library / application / organization), parameters, evidence (scenarios and results, commit, date, versions, latency and components, ledger mode, seam surface and exemptions, inventory items), and gaps. Deferred to later phases in v9, recorded not deleted: OSCAL output (as a component definition, never a whole SSP), 20x KSI output, `--diff`, the event-store ledger mode ("bring your own store"). Kept: all four adapters including OpenFGA and its projector, the ledger in Ecto and none modes, `mix turnstile.review`.

## Technical calls left to the decisions file (orchestrator's recommendations, not owner decisions)
Holes #1, #3, #9, #10, #14, #16, #17, #24 (seam), #6 (fact mapping shape), #4/#5 (results file from an ExUnit formatter; latency reported never asserted), #20 (component definition, deferred), #21 (`priv/conformance/` per adapter). Use each hole's "close it with" line unless the writer finds a better closure and records why.
