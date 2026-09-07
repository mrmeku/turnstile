# Turnstile — plan, v7
*Mode: Explanation. This file says what Turnstile is, what it means by each of its words, what it guarantees, and why each decision went the way it did. The tables, numbers, and mechanics the first implementer needs are in `REFERENCE.md`, cited from here by section; they move into package docs as the packages appear. Open decisions are marked ⟨open n⟩ and collected at the end; claims to check against the pinned sources are marked ⟨verify⟩.*

Turnstile is an authorization library for Elixir, for teams shipping a cloud service that a 3PAO will assess against the FedRAMP Moderate baseline, on either of FedRAMP's two tracks. The application keeps its authorization mechanism behind a port; the library ships adapters for three mechanisms; each adapter arrives with an example application, that application's control implementation statements, and the evidence behind them.

The bet: an assessment is passed with evidence, and a library can generate most of it if it owns two things — the history of who was allowed what, and the record of every decision it made.

## Who it is for

The engineering lead at a cloud service provider who has been handed the Moderate baseline and an assessment date. Each question they will ask is a feature, not a README paragraph; the control asking the same thing follows.

1. What happens when a check cannot be made — does it deny? (AC-3)
2. Can I prove every request was checked, not most of them? (AC-3; "always invoked", AC-25)
3. Who can access what today, and who could on a date last year? (AC-2 account review, AC-6(7))
4. Can I show every decision, and every change to who is allowed what? (AU-2, AU-12, AC-2(4))
5. When I revoke access, how long until it takes effect, and can I prove the number? (AC-2, PS-4)
6. Can I write the control implementation statements without inventing anything? (the SSP)
7. Can my compliance team, and the 3PAO, read what the engineers built? (the SSP and the SAR)
8. Can I keep producing this — monthly under Rev 5, quarterly in a 20x Ongoing Authorization Report? The generator runs in CI, so the answer is the same artifact, dated.

## Words

Three vocabularies, at three speeds, each kept where its speed is harmless.

The port's words — **subject, object, operation, environment condition** — are NIST SP 800-162's. They do not move, and they are the only vocabulary core, the events, and the adapters speak, besides Ecto's query language. Control identifiers — AC-3, AU-2 — are SP 800-53's: a control keeps its number for life, withdrawn ones are never reused, revisions add. Scenarios cite them. FedRAMP's program words — SSP, control implementation statement, implementation status, origination, POA&M, CRM, parameter, 3PAO, authorization boundary, inventory, Key Security Indicator, Ongoing Authorization Report — change on a cadence of months and their identifiers are being restandardized. Only the generator speaks them, and it reads them from three pinned sources — the SP 800-53 catalog, the FedRAMP Moderate profile, the 20x machine-readable docs — named in one file; bumping a pin is a procedure whose output is the lint's diff of affected scenarios (REFERENCE §12). A revision is a dependency bump, not a remodel.

Two words are reserved. *Adapter*, never *provider*, which is FedRAMP's word for the cloud service provider. *Assessment-ready*, never *compliant*, and never *FedRAMP Ready*, which was a designation.

## The question

Every access question has one shape: a **subject** — a user, a non-person entity, or a privileged user — an **object**, an **operation**, and the **environment**, facts about the moment. The port supplies the environment facts only it can know, the time among them, from a clock the tests replace; the caller supplies the rest, such as when the session last re-authenticated. A missing caller fact denies.

The port answers in five ways. `authorize` returns a verdict with a reason for one object; `check`, the verdict alone; `batch`, verdicts for many; `scope`, for a collection, returns the rule a row must satisfy — an Ecto `dynamic`, which can only be attached to a query with `where` and so can only narrow it, inspects faithfully, and may contain subqueries; `explain`, optional per adapter, names what matched. Derived in core: `filter`, a batch over a list, and `review`, who can do what across a population — `scope` per subject where Ecto is present, `batch` over a supplied population where it is not.

Guarantees the port keeps regardless of adapter, tested by Tier 1: deny by default; fail closed — an unreachable engine denies with its own reason, and nothing raises on the request path but a programming error; every call emits a decision event; privileged users and non-person entities take their own paths and emit their own events, and a privileged user is a separate account, not a flag (AC-6(2)); every data access is mediated, which is the seam's job below.

## Decisions

A decision is what the port said, when, from what state, under which rules. Its record carries the subject, the object type and id, the operation, the verdict and its reason, the adapter, the policy version, and the ledger position in force. It does not carry attribute values: the position is what replay needs, and nationality does not belong in a log stream.

For a collection the decision is a rule, not a list of rows. The record names the object type and the enforced `dynamic`; replay recomputes the rows from position plus rule and never stores them. What actually happened is an outcome recorded afterwards — rows returned, rows affected. A batch is one record for N objects; a review is one record. Where "who read this document" must be answerable, that is a single-object read, and the example makes opening a document one. Record shapes and caps: REFERENCE §7.

## Facts

An authorization fact is anything a decision depends on that the application can change. Core knows four kinds, in 800-162's words: a subject attribute set or cleared; an object attribute set or cleared; a subject–object relationship granted or revoked; a policy version published. Nothing in core names a program or a marking. Each domain maps its own schemas onto the four kinds through a **fact mapping**, field by field: a fact schema declares which of its columns are facts, and only a change to one of those columns is a fact. A bookkeeping column is not one. The invariant this yields, and the seam and ledger are built to keep: **the ledger grows with what changed, not with what ran.**

Policy versions are facts because rules change, and replaying a March decision under June's rule answers the wrong question. A policy-version event is a dated pointer — adapter, version identifier, content hash, when, author or approval — carrying the rule's text by value only when it is small: a policy expression, a YAML file, a role table. Otherwise it carries the hash and a pointer into the store where the rule lives: git for rules in code, the migration and the database catalog for Postgres, the policy repository and the sidecar's memory for Cerbos. Decision records name the version; only the rare policy event holds bytes (REFERENCE §5).

## The ledger

The ledger is a behaviour in core: append a fact event, read fact events in order from a position, report the current position. Current state is a fold over it; state at a time is the fold stopped there. **Replay** is state at a time plus the policy version in force then, and it reproduces any decision — which no adapter can do alone, since code keeps nothing, a database keeps nothing without temporal tables, and a policy engine versions its rules but not the attributes it was sent. Decisions are reads, so they are a second stream beside the ledger, each stamped with the position it saw.

Three modes, chosen by the application and printed by the generator:

- **Event store.** An event-sourced application's own store is the ledger, read through its fact mapping. It needs no Ecto; completeness is the application's claim about its store.
- **Ecto ledger** (`turnstile_ledger`). The seam records one fact event per changed fact field in the same transaction as the write, into a library-owned table the database keeps append-only by grant. It begins at **genesis** — every current fact written as an event at position zero, stamped with the date and the migration — and replay before genesis is "not available" by construction. **Reconcile** folds the ledger against the tables on an interval and reports **drift**: facts changed outside the seam.
- **None.** The tables are the only truth. Revocation latency is still measured; history, drift, and automated account audit print as things the application must provide.

Every fact and decision event is emitted through telemetry to the organization's log pipeline and SIEM; that copy is the centralized audit record and lives under the SIEM's retention. The ledger is not: it is complete for the life of the system, or replay stops being exact. Mode claims, positions, and the reader: REFERENCE §9–10.

## The seam

The reference monitor of 1972 must be always invoked, tamperproof, and small enough to verify. The port is the small part. The **seam** is what makes "always invoked" a runtime fact rather than a code-review outcome: the application's own Repo module, extended by core, refuses any call that carries neither a decision nor a named exemption, applies `scope`'s rule to every query, and records fact events for declared fields in the same transaction as the write. One seam, three guarantees — always invoked, scope fidelity, no fact without an entry. An **audit mode** logs instead of refusing, and its output is an adopting application's inventory of unchecked paths. Exemptions are listed in the statement with their reasons.

The seam's shape is proven, not assumed. Core classifies every Repo function — mediated through the query hook, overridden, wrapped to demand an exemption, or plumbing that touches no rows — and fails compilation on any function it has not classified, so an Ecto release cannot open a hole; its overrides are injected last, so an application's own query hook runs inside ours; a Tier 1 sweep generated from the module re-proves the classification at runtime (REFERENCE §6). What the seam cannot see — SQL that bypasses the Repo module, a second Repo without the extension — two shipped Credo checks flag, advisory only; the claim stays with the seam. Bulk writes to fact fields go through a declared API that skips rows whose value did not change, so a million-row sync that changes nine facts records nine (REFERENCE §8).

## Audit

Two streams, both in the shape AU-3 asks of an audit record: type, time, source, outcome, identity, and a request or session identifier. Every port call is a telemetry span: `:start` is the decision, `:stop` the outcome, `:exception` the failure — so an attempt is on record even when the query never completes, which is what AU-2's "successful and unsuccessful" means. Records are **per operation, never per row**: a bulk write that changes twenty thousand facts writes twenty thousand ledger rows, because replay needs each, and one audit record carrying the count and the operation id the rows are indexed by. The library ships a Logger handler and owns no store. The example ships a hash-chained store whose chain head rides in every emitted record, so the SIEM's copy anchors a chain that would otherwise be rewritable by anyone who can write the database. Emission is total; forwarding is a printed setting, and denials, writes, and privileged operations are never sampled. Sizes, caps, and shape tests: REFERENCE §7.

## Adapters

Three, named for where the rules live, because that — not the access-control model — is what differs in enforcement, in who may change a rule, and in what each costs inside an authorization boundary, where every engine is an inventory item with its own scanning, hardening, and controls to answer for.

- **Rules in code** — `turnstile_code`. Elixir modules; a deploy is a policy version; enforcement is the seam. First, because RBAC is what the baseline expects: AC-2(7) offers a role-based or an attribute-based scheme, AC-3(7) is the catalog's RBAC enhancement, and what fails assessment is a *single* role, which cannot satisfy AC-5 or the AC-6 family. Its role→permission table is declared data, enumerable for review; attribute predicates sit beside it for the rules roles cannot express.
- **Postgres row-level security** — `turnstile_postgres`. Policies in migrations, enforced by the database whether or not the application asked; write gates need no application code. Postgres by definition.
- **Cerbos** — `turnstile_cerbos`. Policies as files a team that does not ship code can own, test, and version; a stateless sidecar decides; its query plan compiles to a `dynamic`; its own decision log is reconciled against the port's, and any difference is a drift scenario.

Code and Postgres are the recommended pair; Cerbos is for teams whose rules are owned by people who do not write Elixir. A relationship graph (OpenFGA) was considered and dropped on boundary cost — a server and a second store holding copies of the facts — in a domain of programs, lists, controls, and dates; the ledger and projection behaviours leave room for it.

Admission for any adapter: self-hosted, inside the boundary; no facts in tokens — the identity provider contributes the subject and nothing else, because a role in a token is frozen until expiry; deny on failure; an inventory item. Each declares a capability per scenario, a default origination profile, its parameters, its inventory item, and its measured **revocation latency**: the time from a revoking fact or policy change to the first denied request, measured end to end by Tier 1, decomposed into commit, policy propagation, replica lag, and cache, and compared with the FedRAMP-assigned PS-4 value ⟨verify⟩. Every adapter's decision half is database-free; its `scope` half needs Ecto. Comparison and notes: REFERENCE §4.

## The line

Opinionated below the port, neutral above it.

Below: Ecto is required for the seam and for `turnstile_ledger`, without apology — a seam is the only way a library proves "always invoked," and a ledger the only way it records history. Postgres is the reference database and the only one the suite runs; the ledger's few database-dependent mechanisms live in a dialect module, `Postgres` and `Generic` shipped and no more; the RLS adapter is Postgres. The statement prints the database, the dialect, and `tested` or `untested`.

Above: `authorize`, `check`, `batch`, `explain`, the events, the ledger contract, policy versions, `review` over a population, and the generator touch no database, and a compile-time `boundary` rule keeps it so.

Two altitude tests; if either needs a change in core, core is too low. *Bring your own adapter*: implement the adapter behaviour, ship a declaration, pass Tier 1, and the generator prints your statement. *Bring your own store, or none*: an event-sourced application on Cerbos with no Ecto produces a statement — forgoing `scope` and the seam, with mediation, drift, and point-in-time review printed as its own claims.

What the library makes an adopter use: Ecto for the seam; a Repo module extended by core, because a wrapper breaks every tool that expects a real `Ecto.Repo`; Postgres for the tested path and for RLS; a Postgres to run Tier 1 against — the repo's own suite gets one from its Nix shell; two Credo checks. Anything beyond that is a request, not a plan.

## The example: controlled unclassified information

CUI is what a federal system protects below the classified line — information a law or regulation says must be safeguarded, marked with its categories, restricted by dissemination controls, decontrolled on a date or an event — governed by 32 CFR Part 2002 and the NARA Registry, and requiring Moderate confidentiality, which is why the baseline. It was chosen because its rules exercise each mechanism differently: a write the database can refuse, a rule a policy team should own, a derived marking a stateless engine cannot compute. And because it is what FedRAMP exists to protect. The word is assessment-ready, never compliant.

```
Agency ──< Office(designating) ──< Program ──< Assignment(user, role: lead | member)
Office  ──< OfficeRole(user, role: designator | approver)
Program ──< Document(designated_by: Office, marking: Marking, decontrol: date | event | nil)
Document ──< Portion(marking: Marking)                      ⟨open 1⟩
Marking  = (categories: [Category], controls: [Control], list: [User])
Category(name, specified?: bool, implied_controls: [Control])
Control  : federal_only | no_foreign | named_list | releasable_to([country])
User(employment: federal | contractor, nationality)
```

The Agency is the tenant. Access is by lawful government purpose, modeled as assignment to a program (C1). Dissemination controls narrow it below that default; four are modeled, one per shape of test on the subject — an attribute equals a value (FED ONLY), matches the designating agency's (NOFORN), is in the object's list (REL TO), or the subject is on a per-document list (DL ONLY) — and all must hold (C2); the rest of the Registry are the same four shapes with other values. Specified categories imply controls, computed and never copied (C3). Decontrol ends the controls but never the lawful-purpose rule (C5). A marking change needs a designator (C7), a fresh re-authentication (C8), and a different approver (C9). A privileged user may read past C1 with a justification that is logged and reported — never unconditionally (C10). Everything is evaluated at every check (C11), enforced within the revocation clock (C12), and `scope` returns exactly what `check` allows (C13). Portion marking and the banner rule (C4) are ⟨open 1⟩. Training is a procedure the organization evidences (AT-3), not a fact the library checks. Lists show titles and banners under `scope`; opening a document is a per-object read. Full tables: REFERENCE §2–3.

## Evidence

A **scenario** is a test whose name is a sentence, citing a control in the Moderate baseline or a KSI — marked when it cites beyond the baseline — and the lint checks every citation against the pinned sources. Scenarios every adapter passes identically are kept, because a buyer checks them off; parameters a control leaves open are configuration the scenario reads, never constants in a rule. Groups follow what a 3PAO examines: enforcement, least privilege, separation of duties, revocation and expiry, decision audit, access review, re-authentication, emergency override, change control on policy, inventory (ids: REFERENCE §1).

Two tiers. **Tier 1**, in core, proves the port's guarantees, the seam, and the ledger over a neutral fixture, on Postgres and nothing else, with shape tests — query, record, and row counts — checked but not cited; any adapter that passes earns a statement with no example work. **Tier 2** is the CUI scenarios, run once per adapter.

`mix turnstile.assess` ⟨open 2⟩ folds declarations, results, configuration, and the pinned sources into, per control: the control implementation statement and its implementation status; **origination**, in the SSP's own values, defaulted per adapter and declared by the provider, because the SSP is theirs; the **responsibility split** — library implements, application must, organization must — which is a different axis from origination and becomes the CRM; parameters, FedRAMP-assigned apart from provider-chosen; the evidence — scenarios and results, commit, date, versions, latency, ledger mode, database and dialect, pinned-source versions; the seam's surface and exemptions; inventory items; and a POA&M row for every gap, saying what would close it. Two profiles from one declaration — **Rev 5**, as markdown and an OSCAL SSP with POA&M and CRM, and **20x**, as the validating scenarios and results per KSI in the machine-readable shape — because both tracks cite 800-53, and under 20x the conformance suite *is* the validation code a 3PAO reviews. `--diff <ref>` prints what changed between two statements: the adoption's progress bar and the quarterly report's delta. `mix turnstile.review` prints who can do what, today or, with a ledger, on a date.

The library does not claim authorization status, own identity, own the audit store, decide origination, or promise portability it has not tested.

## Adoption

Starting point: Phoenix and Ecto, a JWT whose claim carries one role, a plug that checks it. Every step ships alone; the statement after each is the progress bar.

| Step | Change | Earns |
|---|---|---|
| 0 | Add `turnstile_core` and its Credo checks; run the generator; seam in audit mode | The all-red statement; the inventory of unmediated calls |
| 1 | The token carries identity only; a plug resolves roles and attributes per request | Revocation latency falls from token lifetime to one request — AC-2, PS-4 |
| 2 | The one existing check goes through the port: `turnstile_code`, one role, one permission | Every request evented; deny by default — AC-3, AU-2, AU-12 |
| 3 | Seam from audit to enforce; clear the list | Always invoked — AC-3; AC-25 beyond baseline |
| 4 | Declare the role→permission table: a privileged and a non-privileged role at least, security functions privileged, privileged users on separate accounts, every action naming its operation | AC-5; AC-6(1), (2), (5), (10) |
| 5 | `scope` on list queries through the seam | Tenant isolation proven — AC-3; C13 |
| 6 | Support and operator access through the audited override | AC-6(9), AC-2(2) |
| 7 | Re-authentication for sensitive operations | IA-11 |
| 8 | `mix turnstile.review` | AC-2, AC-6(7) — current state |
| 9 | Add `turnstile_ledger`; declare fact fields; run genesis | AC-2(4), AU-9; history from the genesis date |
| 10 | Postgres RLS beneath, or Cerbos when policy ownership leaves engineering | Origination changes; the statement regenerates |

An application without Ecto walks steps 1, 2, 4, 6, 7, and 8; the rest print as its own claims, and event-store mode is how it gets history.

The example is built by walking this path. Phase 2 starts from tag `v0-jwt-single-role`, a plain Phoenix application with no Turnstile in it; each step is a tag with its generated statement committed beside it; the adoption guide is the annotated tag list; CI regenerates each tag's statement and diffs it against the committed one so the guide cannot rot silently. Postgres and Cerbos are `v10a` and `v10b`. ⟨open 3⟩

## Packages and conventions

```
turnstile/
  PLAN.md · REFERENCE.md · CODE.md · TESTING.md · README.md · flake.nix · flake.lock · .envrc
  docs/        context-map.md · glossary-index.md · references.md · writing.md · adr/
               how-to/adopt.md · how-to/bump-sources.md
  apps/
    turnstile_core/       port, events, clock, ledger and projection behaviours, the seam (surface
                          classification, audit mode, fact-recording hook), Credo checks, the top-layer
                          boundary rule, Tier 1 — depends on ecto, not ecto_sql
    turnstile_ledger/     the Ecto ledger: table, genesis, reader, reconcile, replay, bulk fact API,
                          dialects Postgres and Generic — ecto_sql
    turnstile_assess/     the generator: declarations in; SSP (markdown, OSCAL), POA&M, CRM, KSI JSON out;
                          priv/sources.exs and the pinned sources; the lint; review and diff tasks
    turnstile_code/       rules in code: declared roles and permissions, attribute predicates
    turnstile_postgres/   row-level security, write gates, session settings, policy versions from migrations
    turnstile_cerbos/     attribute declarations, query plan to dynamic, policy versions, decision-log reconciliation
    turnstile_example/    the CUI application, built by migration from tag v0; Tier 2; reference audit store;
                          committed statements; per-adapter notes
```

Engineering: Elixir 1.20 with its type checker at the strictest setting, no Dialyzer; the adapter bound at compile time; a Nix flake pins Elixir, OTP, Postgres, and Cerbos and is the only documented path for development and CI — no Docker, no `.tool-versions`; `boundary` in core for the top-layer rule. Testing: every test owns its state, an ephemeral Postgres per run, `async: true` by default (`TESTING.md`).

Documentation: every file declares one Diátaxis mode and stays in it; one glossary per bounded context, colocated with its package, translations at boundaries — the assessment context's glossary is FedRAMP's vocabulary, and its boundary is where the engineers' words become the 3PAO's; decision records only where a newcomer would reopen the decision; foreign concepts get two sentences and a link; the banned-words lint, which also enforces the two reserved words; test names are the scenario sentences.

## Phases

1. **Core.** Port, events, clock, ledger and projection behaviours, the seam with its surface check, the Credo checks, the boundary rule, a fake adapter and an in-memory ledger, Tier 1 on the ephemeral Postgres, shape tests included. The generator exists from day one with the pinned sources and the lint and prints every control unknown. Glossaries and the first decision records before code.
2. **Rules in code and the example.** `turnstile_code`; the example from `v0` through `v8`, tag by tag, with the reference audit store. First real statement, ledger mode none.
3. **The ledger, then Postgres.** `turnstile_ledger` — recording through the seam, the bulk API, both dialects, genesis, the reader, reconcile, replay — and `v9`. Then row-level security, write gates, session settings, append-only by grant; `v10a`.
4. **Cerbos.** Policy versions as facts, plan to `dynamic`, decision-log reconciliation; `v10b`.
5. **Point-in-time review**, drift scenarios, `--diff`.
6. **Outputs validated** — OSCAL against FedRAMP's templates, KSI JSON against the 20x docs — the README with each adapter's statement, the adoption guide as the tag list with its CI check.

## Decisions, each with the alternative it rejected

- FedRAMP on two tracks over one catalog, 800-53 ids as the key — over Rev 5 alone.
- The Moderate baseline, because CUI needs it; CUI over the classified domain.
- Rules in code first, because RBAC is the baseline's default and a single role is not RBAC — over treating RBAC as the lesser adapter.
- Three adapters, named for the mechanism; OpenFGA rejected on boundary cost.
- Four admission rules — over hosted engines, facts in tokens, and allow-on-timeout.
- Fact events in 800-162's terms, declared per field, the domain mapped at its boundary — over domain-shaped events in core and over table-level facts.
- Ecto in core and `scope` as a `dynamic` — over a filter language of core's own, which guaranteed narrowing and a faithful record but could not express subqueries and cost a language and two compilers; the price is ORM independence, which the port never needed.
- Mediation at the Repo seam, at runtime, surface classified at compile time, overrides injected last — over a compile-time heuristic and hand-listed overrides.
- Two Credo checks for the seam's two blind spots, and no more — over re-deriving statically what the seam proves.
- Revocation latency measured end to end — over projection lag.
- The ledger optional with three modes, genesis as its origin, append-only by grant, the library recording rather than owning — over a fold that writes the application's tables.
- Policy-version events as dated pointers, content only under a cap — over bundles in the ledger.
- Audit records per operation and ledger rows per fact, with a declared bulk API that skips unchanged rows — over per-row audit records and over refusing bulk writes outright.
- Sequence positions with a visibility-safe reader — over a serialized counter, which a dialect may still choose.
- The line: opinionated below the port, database-free above it by compile-time boundary — over portable-everything and over Postgres-only.
- The library emits and the example stores, chain anchored in the SIEM — over owning a store.
- Origination declared by the provider; the responsibility split as the CRM's input — over conflating the two.
- Pinned sources with a bump procedure — over hard-coded citations.
- The example built by migration, tags as the guide, a CI diff as the guard — over a separate guide.
- Nix for the toolchain and every service, and an ephemeral Postgres cluster per test run — over Docker Compose and a shared development database.
- Shape tests that count queries, records, and rows, plus one generously bounded tripwire, with benchmarks on demand — over timing budgets in CI, which measure the runner.
- The scenario bar and two tiers; training out; four controls, one per shape; adapter over provider; assessment-ready over compliant.

## Open decisions

1. Portion marking: document-level only, or optional portions and the redacted read. Deferred.
2. Names — the library, `Turnstile` throughout, and the assess task. The author will propose them.
3. The adoption guide's form: tags with a CI check, or the "before" application as a fixture. Start with tags; decide at the end of Phase 2 from the CI cost.
