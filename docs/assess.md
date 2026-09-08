# The assessment generator, deferred
*The design of `turnstile_assess`, the package that will fold what the library knows into control implementation statements and their evidence. It is not part of the MVP. This file holds everything the plan said about it so the idea returns intact, as its own stage after the last one in `docs/delivery.md`. Nothing here is built, and no document other than this one and the deferred list in `PLAN.md` refers to it.*

## What it is for

The engineering lead who has been handed the Moderate baseline and an assessment date asks two questions the library's runtime cannot answer on its own: can I write the control implementation statements without inventing anything (the SSP), and can I keep producing them, monthly under Rev 5 and quarterly in a 20x Ongoing Authorization Report. The generator runs in CI, so the answer is the same artifact, dated. It emits the Rev 5 statement first; the 20x report follows when the 20x docs define a results schema.

## Two tracks, for orientation

**Rev 5**: an SSP with a control implementation statement per control, assessed by a 3PAO, monthly continuous-monitoring deliverables, OSCAL accepted. **20x**: Key Security Indicators, sixty-one for Moderate at the pinned release, each mapped to 800-53 controls, validated by automation the 3PAO reviews, reported quarterly in an Ongoing Authorization Report; the Moderate pilot ran over the winter of 2025 to 2026. Impact-level names are being replaced; the level is a profile input and appears in no module name.

## Words the generator alone speaks

FedRAMP's program words (SSP, control implementation statement, implementation status, origination, POA&M, CRM, parameter, 3PAO, authorization boundary, inventory, Key Security Indicator, Ongoing Authorization Report) change on a cadence of months and their identifiers are being restandardized. Nothing in the library speaks them. The generator reads them from three pinned sources named in one file, so a revision is a dependency bump, not a remodel.

**Assessment glossary**: control, enhancement, parameter, implementation status, origination, baseline, profile, SSP, SAR, POA&M, CRM, 3PAO, authorization boundary, inventory, continuous monitoring, Key Security Indicator, Ongoing Authorization Report.

| Term | Meaning |
|---|---|
| Responsibility split | Library / application / organization, who builds it; feeds the CRM |
| 20x / KSI / Ongoing Authorization Report | The automation-first track / its outcome statements / its quarterly report |
| OSCAL | NIST's machine-readable format for catalogs, profiles, SSPs, results, POA&Ms |
| Pinned sources | Specific releases of the catalog, the profile, and the 20x docs, named in one file |
| Lint | The check on citations and skips |
| Statement | The generated control implementation statements of one thin application, with their evidence |

## Pinned sources and the lint

`apps/turnstile_assess/priv/sources.exs` pins three releases and the files sit beside it: the SP 800-53 catalog (OSCAL; 5.2.0 at the time of writing), the FedRAMP Rev 5 Moderate baseline profile (OSCAL, from the fedramp-automation repository), and the FedRAMP 20x machine-readable docs. The lint checks every scenario's control id against the catalog, its baseline membership against the profile, and its KSI id against the docs; the 20x docs are read by the lint alone until the KSI output returns. Enhancement membership in the Moderate profile is checked permanently against the pinned profile.

Each scenario group maps to a 20x family: enforcement, least privilege, separation of duties, revocation, access review, re-authentication, and emergency override to KSI-IAM; decision audit and emergency override to KSI-MLA; change control on policy to KSI-CMT; inventory to KSI-PIY.

**Bump procedure.** Update the pin and file; run the lint; its diff lists scenarios whose citations changed, were withdrawn, or gained a KSI; re-cite; regenerate; commit the diff with the bump. A `sources` CI job runs on a change under `apps/turnstile_assess/priv/`: `mix turnstile.assess --citations` in `apps/turnstile_example/` regenerates `priv/citations.md`, every scenario's controls resolved against the pinned catalog and profile with baseline membership and KSI ids, and `git diff --exit-code` on it requires the lint's diff to be committed with the bump.

**Lint modules.** `Turnstile.Conformance.Scenario` reads a scenario from source without compiling it: id, sentence, rule, controls, group, file, line; `read/1` over globs and `parse/2` over one file by walking the AST. `Turnstile.Conformance.LanguageLint` has `unknown_terms/2`, `unknown_rules/2`, `unknown_scenarios/2`: three lists that are empty when the suite's words match the glossary and the declaration; `unknown_scenarios/2` compares the capability declaration with the scenarios present. `Turnstile.Conformance.Sources` is the behaviour the `scenario` macro would validate `control:` ids against at expansion; `turnstile_assess` implements it over the pinned sources. The AST reader is one of the allowlisted uses of reflection in `docs/code.md` §4. A second word for one concept becomes a lint failure once the glossary exists.

## Inputs

Three. Declarations, which are Elixir modules read at compile time of the thin app: the thin app's capability declaration per rule (kept in the MVP, `docs/reference.md` §3), the adapter's declaration extended with its inventory item (name, version, where it runs, its log location, for the Integrated Inventory Workbook, CM-8), its default origination profile, and its parameters with their defaults (for OpenFGA: consistency per operation, drain interval, the `ListObjects` cap; for Cerbos: the policy poll interval), and the thin app's origination overrides. `results.json`, written by the ExUnit formatter `Turnstile.Assess.Formatter` per run. And `%Turnstile.Config{}` plus the pinned sources.

The formatter runs under `mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter` beside the default formatter and writes one file per run at the path in `TURNSTILE_RESULTS`, default `tmp/results.json`:

```json
{
  "run_id": "2026-09-07T14:03:11Z-a1b2c3",
  "thin_app": "example_postgres",
  "adapter": "Turnstile.Postgres",
  "ledger_mode": "ecto",
  "executed": 60,
  "skipped": 0,
  "failed": 0,
  "scenarios": [
    {"id": "enf-01", "outcome": "passed", "skip_reason": null,
     "capability": {"level": "native", "by": "database", "note": ""}, "latency": null},
    {"id": "rev-01", "outcome": "passed", "skip_reason": null,
     "capability": {"level": "native", "by": "database", "note": ""},
     "latency": {"total_ms": 4, "poll_interval_ms": 1,
                 "components": {"commit": 3, "replica_lag": "not measured", "cache": "not measured"}}}
  ]
}
```

`outcome` is `passed`, `failed`, or `skipped`; `skip_reason` is `null`, `{"capability": "c3"}` naming the declared rule, or `"needs_ledger"`; `capability` is the thin app's record for the rule the scenario tests; `latency` is present on the revocation-latency case only. The schema is a module with a `@typedoc`, frozen with the contracts, and its keys are among the freeze tests. `results.json` and `evidence.json` are edges in `docs/code.md` §2's sense, each with one `from_map/1`.

**The skipped-scenario invariant, formatter form.** `mix turnstile.assess` reads `results.json` before it generates anything and fails when `executed` is zero, when any scenario is skipped without a declared `unsupported` or `limited` capability naming its rule, or when a skip's reason is anything but a declared capability or `needs_ledger` in a mode-none run. `--check` runs that check alone and writes no statement. The MVP keeps the same invariant as a generated count test (`docs/testing.md` §6); the formatter form adds the per-scenario record the statement cites.

## What it produces

`mix turnstile.assess` folds declarations, results, configuration, and the pinned sources into, per control: the control implementation statement and its implementation status; **origination**, in the SSP's own values, defaulted per adapter and declared by the provider, because the SSP is theirs; the **responsibility split** (library implements, application must, organization must), which is a different axis from origination and becomes the CRM; parameters, FedRAMP-assigned apart from provider-chosen; the evidence, meaning scenarios and results, commit, date, versions, latency and its components, ledger mode, database and dialect, pinned-source versions; the seam's surface and exemptions; inventory items; and a POA&M row for every rule the thin application declares unsupported, saying what would close it. A rule enforced by another component of the same stack is native, with that component named in the origination column, and "not applicable" earns no row. `limited` prints its note beside the scenario. One profile first: Rev 5, as markdown.

**Statement files.** Two per thin app, under `apps/example_<adapter>/statement/`:
- `statement.md`: deterministic, committed. Per control as above; the scenario ids and outcomes; ledger mode, database and dialect; the seam's surface and exemptions; inventory items; a POA&M row for every `unsupported` rule; for Postgres, the defense-in-depth note. CI regenerates it after the Tier 2 run and fails on `git diff --exit-code`.
- `evidence.json`: volatile, regenerated per run and committed with the body whenever the body is regenerated, never diffed: commit, date, versions (toolchain, engine, pinned sources), latency with components and the poll floor, the counter row's serialization cost, `run_id`.

The README's four statements are the four bodies, included by reference, side by side, so a team chooses from the evidence. The thin-app CI job adds, after Tier 2 with the formatter: `mix turnstile.assess`, then `git diff --exit-code statement/statement.md`; `evidence.json` is never diffed. `example_code` runs the formatter step twice, once per ledger mode, the mode-none run checked by `--check`. Each thin app's README says where its statement is and how it is regenerated.

**SSP vocabulary printed.** Implementation status: Implemented, Partially Implemented, Planned, Alternative Implementation, Not Applicable. Origination: Service Provider Corporate; Service Provider System Specific; Service Provider Hybrid; Configured by Customer; Provided by Customer; Shared; Inherited from pre-existing authorization. Example defaults: programs, lists, and designators an agency sets, Configured by Customer; CUI training and CUI marking rules (32 CFR 2002), Service Provider Corporate; what the library or application implements, Service Provider System Specific. POA&M columns: weakness, detection source, remediation plan, scheduled completion, milestones, status.

## What the statement prints, by mechanism

Every item below is a fact the runtime already has; the generator is what puts it on the page.

- The port: that every call is evented, cited as the AU-2 FedRAMP-assigned parameter for authorization checks, data access, data changes, and permission changes ⟨verify Rev 5 wording⟩.
- The seam: the classification with counts, the Ecto version, a hash of the surface, protected schemas, unprotected schemas, carried relations, the per-call exemptions with their reasons and the count of library exemptions by table, the owner-role repo, the static-check results as advisory.
- The ledger: the mode and its claims (`docs/reference.md` §10), the genesis date, the append-only grant, the catalog check's result, the counter row's measured serialization cost, and for mode none the claims the application must make itself (drift detection, point-in-time review, AC-2(4) account-management audit) with a POA&M row for an adapter that requires a ledger.
- Dialect: the database, the dialect, and `tested` or `untested` from the suite's own record.
- Policy versions: which artifact a version is on this adapter, and whether content is by value or by pointer; that replay of code rules depends on the repository's retention.
- Caps and configuration: every field of `%Turnstile.Config{}` except secrets; the caps.
- Revocation latency: the measured total and its components, the poll interval as the floor, compared with the FedRAMP-assigned PS-4 value ⟨verify⟩ against C12's configured maximum; never asserted.
- Postgres: the defense-in-depth note, write gates needing no application code; never a rule and never a POA&M row.
- OpenFGA: two inventory items (the server and its datastore, one engine if the datastore shares the application's Postgres instance), the drain interval, the reconcile interval, consistency per operation, the `ListObjects` cap and that `scope` above it is limited, and each store swap after a rebuild as a dated change.
- Cerbos: the sidecar as one inventory item and the policy poll interval as the policy-propagation latency.

## The inventory group

Two scenarios return with the generator, in a group `inv` citing CM-8: `inv-01`, the statement lists every engine inside the boundary with its version, where it runs, and its log location; `inv-02`, the engine version printed equals the version the flake pins.

## Testing the generator

Golden files with plain assertions under `apps/turnstile_assess/test/golden/` for the smaller outputs (POA&M rows, CRM rows, a single control's statement), rewritten by `TURNSTILE_UPDATE_GOLDEN=1 mix test` and reviewed like any other diff; the committed `statement.md` per thin app is the golden file of the whole output. A test asserts the lint rejects a scenario citing `AC-99` and one citing a control outside the Moderate baseline. The skeleton's gate: the formatter writes a non-empty `results.json`; `--check` fails on zero executed scenarios; `mix turnstile.assess` with no results prints every baseline control "unknown".

## Decisions carried with it

- Origination declared by the provider; the responsibility split as the CRM's input; not conflating the two.
- Pinned sources with a bump procedure; not hard-coded citations.
- Statements from a results file an ExUnit formatter writes, a deterministic body and a volatile evidence file; not a statement per tag.
- Capability declarations stay in the thin application; only `unsupported` earns a POA&M row.

## After it

- The OSCAL component definition, never a whole SSP: returns when a customer asks for OSCAL import; validated with the pinned fedramp-automation constraints.
- The 20x KSI output: returns when the pinned 20x docs define a results schema the lint can check.
- `--diff <ref>`: returns when two dated statements of one thin application exist to compare; it reads two `evidence.json` files.

## Return condition

The generator returns as one stage after the last stage in `docs/delivery.md`, once the four thin applications run and their scenarios, capability declarations, and latency measurements exist for it to read. It changes no frozen interface: the formatter observes tests, the declarations extend modules that exist, and the statement is a file the runtime never reads.
