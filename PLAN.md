# Turnstile: plan, v9
*This file says what Turnstile is, what it means by each of its words, what it guarantees, and why each decision went the way it did. The tables, numbers, and mechanics the first implementer needs are in `docs/reference.md`, cited from here by section; they move into package docs as the packages appear. Claims to check against the pinned sources are marked ⟨verify⟩.*

Turnstile is an authorization library for Elixir, for teams shipping a cloud service that a 3PAO will assess against the FedRAMP Moderate baseline, on either of FedRAMP's two tracks. The application keeps its authorization mechanism behind a port; the library ships adapters for four mechanisms; each adapter arrives with an example application, that application's control implementation statement, and the evidence behind it. The example is one domain built once and bound four times, one thin application per adapter, so the four statements are four build artifacts that cannot rot.

The bet: an assessment is passed with evidence, and a library can generate most of it if it owns two things: the history of who was allowed what, and the record of every decision it made.

## Who it is for

The engineering lead at a cloud service provider who has been handed the Moderate baseline and an assessment date. Each question they will ask is a feature, not a README paragraph; the control asking the same thing follows.

1. What happens when a check cannot be made: does it deny? (AC-3)
2. Can I prove every request was checked, not most of them? (AC-3; "always invoked", AC-25)
3. Who can access what today, and who could on a date last year? (AC-2 account review, AC-6(7))
4. Can I show every decision, and every change to who is allowed what? (AU-2, AU-12, AC-2(4))
5. When I revoke access, how long until it takes effect, and can I prove the number? (AC-2, PS-4)
6. Can I write the control implementation statements without inventing anything? (the SSP)
7. Can my compliance team, and the 3PAO, read what the engineers built? (the SSP and the SAR)
8. Can I keep producing this, monthly under Rev 5 and quarterly in a 20x Ongoing Authorization Report? The generator runs in CI, so the answer is the same artifact, dated. The first implementation emits the Rev 5 statement; the 20x report is on the deferred list at the end.

## Words

Three vocabularies, at three speeds, each kept where its speed is harmless.

The port's words, **subject, object, operation, environment condition**, are NIST SP 800-162's. They do not move, and they are the only vocabulary core, the events, and the adapters speak, besides Ecto's query language. Control identifiers such as AC-3 and AU-2 are SP 800-53's: a control keeps its number for life, withdrawn ones are never reused, revisions add. Scenarios cite them. FedRAMP's program words (SSP, control implementation statement, implementation status, origination, POA&M, CRM, parameter, 3PAO, authorization boundary, inventory, Key Security Indicator, Ongoing Authorization Report) change on a cadence of months and their identifiers are being restandardized. Only the generator speaks them, and it reads them from three pinned sources, the SP 800-53 catalog, the FedRAMP Moderate profile, and the 20x machine-readable docs, named in one file; the 20x docs are read by the lint alone until the KSI output returns. Bumping a pin is a procedure whose output is the lint's diff of affected scenarios (`docs/reference.md` §12). A revision is a dependency bump, not a remodel.

Two words are reserved. *Adapter*, never *provider*, which is FedRAMP's word for the cloud service provider. *Assessment-ready*, never *compliant*, and never *FedRAMP Ready*, which was a designation.

## The question

Every access question has one shape: a **subject** (a user, a non-person entity, or a privileged user), an **object**, an **operation**, and the **environment**, facts about the moment. The subject struct carries which of the three kinds it is, and the port dispatches on it. The port supplies the environment facts only it can know, the time among them, from a clock the tests replace; the caller supplies the rest, such as when the session last re-authenticated. A missing caller fact denies, and `scope` under a denied precondition returns a rule no row satisfies, with the verdict deny.

The port answers in five ways. `authorize` returns a verdict with a reason for one object; `check`, the verdict alone; `batch`, verdicts for many; `scope`, for a collection, returns the rule a row must satisfy: an Ecto `dynamic`, which can only be attached to a query with `where` and so can only narrow it, inspects faithfully, and may contain subqueries; `explain`, optional per adapter and answered unsupported at runtime where absent, names what matched. Derived in core: `filter`, a batch over a list, and `review`, who can do what across a population: `scope` per subject where Ecto is present, `batch` over a supplied population where it is not.

Guarantees the port keeps regardless of adapter, tested by Tier 1: deny by default; fail closed, so an unreachable engine denies with its own reason, and nothing raises on the request path but a programming error; every call emits a decision event; privileged users and non-person entities take their own paths and emit their own events, and a privileged user is a separate account, not a flag (AC-6(2)); every data access is mediated, which is the seam's job below.

## Decisions

A decision is what the port said, when, from what state, under which rules. Its record carries the subject, the object type and id, the operation, the verdict and its reason, the adapter, the policy version, and two ledger positions: the head at decision time and the position the adapter's state had applied, equal for an adapter that reads the tables, apart by the lag for one that projects them; replay uses the applied one. In ledger mode Ecto the head is one read of the counter row, counted as one query; in mode none there is no head and the position is `nil`. The record does not carry attribute values: the position is what replay needs, and nationality does not belong in a log stream.

For a collection the decision is a rule, not a list of rows. The record names the object type and the enforced `dynamic`; replay recomputes the rows from position plus rule and never stores them. Under row-level security the rule is `true`, the policy version is the migration number, and the record carries a hash of the session settings in force, since those are what the database enforced. What actually happened is an outcome recorded afterwards: rows returned, rows affected. A batch is one record for N objects; a review is one record. Where "who read this document" must be answerable, that is a single-object read, and the example makes opening a document one. Record shapes and caps: `docs/reference.md` §7.

## Facts

An authorization fact is anything a decision depends on that the application can change. Core knows four kinds, in 800-162's words: a subject attribute set or cleared; an object attribute set or cleared; a subject–object relationship granted or revoked; a policy version published. Nothing in core names a program or a marking. Each domain maps its own schemas onto the four kinds through a **fact mapping**, declared with a macro column by column: a fact schema declares, for each column, which of the four kinds a change is, which columns name the subject and the object, and the element type where the column holds a set; and, per row, what insert and delete mean, because a relationship row's existence is the grant and its other columns are attributes of that relationship. Only a change to a declared column is a fact, and the event carries the old value and the new, since replay, reconcile, and the tuple mapping all need both. A bookkeeping column is not a fact. The invariant this yields, and the seam and ledger are built to keep: **the ledger grows with what changed, not with what ran.**

Policy versions are facts because rules change, and replaying a March decision under June's rule answers the wrong question. A policy-version event is a dated pointer (adapter, version identifier, content hash, when, author or approval) carrying the rule's text by value only when it is small: a policy expression, a YAML file, a role table. Otherwise it carries the hash and a pointer into the store where the rule lives: git for rules in code, the migration and the database catalog for Postgres, the policy repository and the sidecar's memory for Cerbos. Decision records name the version; only the rare policy event holds bytes (`docs/reference.md` §5).

## The ledger

The ledger is a behaviour in core: append a fact event, read fact events in order from a position, report the current position. Current state is a fold over it; state at a time is the fold stopped there. **Replay** is state at a time plus the policy version in force then, and it reproduces any decision, which no adapter can do alone: code keeps nothing, a database keeps nothing without temporal tables, and a policy engine versions its rules but not the attributes it was sent. Decisions are reads, so they are a second stream beside the ledger, each stamped with the position it saw.

Positions come from a counter row. Every fact-writing transaction locks one row in a library-owned counter table, takes the next positions from it, and inserts its events with them, so commit order is position order, there are no gaps, and a reader is "from position N". The head is the counter row's committed value, every position at or below it is committed, and replay to the head is exact. The lock serializes fact-writing transactions; that cost is measured and printed in the statement rather than argued about. The same mechanism runs on every database, and the dialect seam stays so a Postgres watermark reader can be added later. The row is named in the configuration, so a test can take its own and async tests never contend.

A **projection** is how an adapter's working state relates to the ledger. For rules in code, Postgres, and Cerbos the state is the application's tables, so the projection is identity and the applied position is the head. For a relationship graph the state is a copy in the engine's own store, kept current by a **projector** that drains the ledger from a checkpoint, advances the checkpoint after every acknowledged write, and writes only the difference between what the fold requires and what the engine holds; it can be rebuilt from position zero into a fresh store beside the serving one, and the swap is a dated change the statement prints. Its lag is a component of revocation latency and its drift is what reconcile compares. An adapter that projects declares that it requires a ledger.

Two modes, chosen by the application and printed by the generator; a third, the application's own event store as the ledger, is deferred and listed at the end:

- **Ecto ledger** (`turnstile_ledger`). The seam records one fact event per changed fact field in the same transaction as the write, into a library-owned table the database keeps append-only by grant. It begins at **genesis**, every current fact written as an event at position zero, stamped with the date and the migration, and replay before genesis is "not available" by construction. **Reconcile** folds the ledger against the tables on an interval and reports **drift**: facts changed outside the seam. A foreign key that cascades into a fact schema would change facts with no entry, so a catalog check at genesis and in Tier 1 refuses such keys.
- **None.** The tables are the only truth. Revocation latency is still measured; history, drift, and automated account audit print as things the application must provide; an adapter that requires a ledger prints as unsupported, with a POA&M row.

Every fact and decision event is emitted through telemetry to the organization's log pipeline and SIEM; that copy is the centralized audit record and lives under the SIEM's retention. The ledger is not: it is complete for the life of the system, or replay stops being exact. Mode claims, positions, and the reader: `docs/reference.md` §9 to §10.

## The seam

The reference monitor of 1972 must be always invoked, tamperproof, and small enough to verify. The port is the small part. The **seam** is what makes "always invoked" a runtime fact rather than a code-review outcome: the application's own Repo module, extended by core, refuses any call on a protected schema that carries neither a decision for that schema's object type nor a named exemption, applies `scope`'s rule to every query, and records fact events for declared fields in the same transaction as the write. One seam, three guarantees: always invoked, scope fidelity, no fact without an entry. Refusal raises `Turnstile.Error.Unmediated`.

Which decision applies to which query is a rule, not a guess. A schema is protected iff it declares an object type. The seam judges a query by its root source: a decision naming a different object type is refused; a preload or association query needs its own decision unless the parent schema declares the association as a carried relation; in a multi-source query every other protected source must be carried by the root. Lookup tables declare no object type and pass without a decision, and the statement lists protected schemas, unprotected schemas, and carried relations.

Exemptions are per call, with a reason, and print in the statement with their reasons. A library-internal kind covers the writes the library makes itself (the ledger's tables, the projector's checkpoint, genesis), and only library callers may claim it. Reconcile, genesis, and test truncation run through a second Repo module the application declares with the owner role, which the seam treats as wholly library-exempt and the statement prints.

The seam's shape is proven, not assumed. Core classifies every Repo function (mediated through the query hook, overridden, wrapped to demand an exemption, or plumbing that touches no rows) and fails compilation, once the module is compiled, on any function it has not classified, so an Ecto release cannot open a hole; its overrides are injected last, and the same after-compile check asserts they are the definitions in force, so an application's own query hook runs inside ours; a Tier 1 sweep generated from the module re-proves the classification at runtime (`docs/reference.md` §6). An adapter may wrap every mediated call and write through `around_query/3`, the seam's fourth extension point; the Postgres adapter uses it to open a transaction where none is open and to set the subject's session settings on every call, so two subjects in one transaction each set their own. What the seam cannot see (SQL that bypasses the Repo module, a second Repo without the extension) two shipped Credo checks flag, advisory only; the claim stays with the seam. Bulk writes to fact fields go through a declared API that skips rows whose value did not change, so a million-row sync that changes nine facts records nine (`docs/reference.md` §8). For a single-row update or delete the seam re-reads the row under the dialect's lock and takes the old value from the re-read, not from the changeset; an upsert on a fact schema is refused with a pointer to the bulk API.

## Audit

Two streams, both in the shape AU-3 asks of an audit record: type, time, source, outcome, identity, and a request or session identifier. Every port call is a telemetry span: `:start` is the decision, `:stop` the outcome, `:exception` the failure, so an attempt is on record even when the query never completes, which is what AU-2's "successful and unsuccessful" means. Records are **per operation, never per row**: a bulk write that changes twenty thousand facts writes twenty thousand ledger rows, because replay needs each, and one audit record carrying the count and the operation id the rows are indexed by. The library ships a Logger handler and owns no store. The example ships a hash-chained store whose chain head rides in every emitted record, so the SIEM's copy anchors a chain that would otherwise be rewritable by anyone who can write the database. Emission is total and nothing is sampled. Sizes, caps, and shape tests: `docs/reference.md` §7.

## Adapters

Four, named for where the rules live, because that, not the access-control model, is what differs in enforcement, in who may change a rule, and in what each costs inside an authorization boundary, where every engine is an inventory item with its own scanning, hardening, and controls to answer for.

- **Rules in code**, `turnstile_code`. Elixir modules; a deploy is a policy version; enforcement is the seam. First, because RBAC is what the baseline expects: AC-2(7) offers a role-based or an attribute-based scheme, AC-3(7) is the catalog's RBAC enhancement, and what fails assessment is a *single* role, which cannot satisfy AC-5 or the AC-6 family. Its role→permission table is declared data, enumerable for review; attribute predicates sit beside it for the rules roles cannot express.
- **Postgres row-level security**, `turnstile_postgres`. Policies in migrations, enforced by the database whether or not the application asked; that write gates need no application code is printed as a defense-in-depth note, not claimed as a rule. Session settings are set inside `around_query/3`; `check` for a write is a select of the update policy's predicate, read from the catalog, under those settings; portions are a second policy on their own table; the thin app's per-rule table names the mechanism for each of C1 to C13. Postgres by definition.
- **Cerbos**, `turnstile_cerbos`. Policies as files a team that does not ship code can own, test, and version; a stateless sidecar decides; its query plan compiles to a `dynamic` over declared attributes, and derived markings fall back to `filter` and are recorded limited, because materializing them would copy what C3 says is never copied; its own decision log is reconciled against the port's, and any difference is a drift scenario.
- **OpenFGA**, `turnstile_fga`. A relationship graph: facts become tuples, rules become an immutable, versioned model, and a projector drains the ledger into the engine's own store, so the adapter requires a ledger. The adapter talks to the server through a client behaviour with an in-memory fake, built first, so the projector's convergence and drift cases run without a server; the projection cases run on the committed repo and drive the drain synchronously. Explanations are paths; implied controls and separation of duties are the cleanest of any adapter; `scope` is a capped `ListObjects`, declared limited; there are no write gates. It costs a server and a datastore inside the boundary (two inventory items, one engine if the datastore shares the application's Postgres instance) and a drain interval inside the revocation clock, and the statement prints both.

Code and Postgres are the recommended pair; Cerbos is for teams whose rules are owned by people who do not write Elixir; OpenFGA is for domains with real hierarchy, or organizations that have standardized on it. The example is one library application bound once per adapter by a thin application, and the four statements sit side by side in the README so that a team can choose from the evidence, not from the marketing: what each adapter enforces without help, what each explains, what each costs, and where each records a gap. The graph adapter's design note is `docs/reference.md` §13.

Admission for any adapter: self-hosted, inside the boundary; no facts in tokens, because the identity provider contributes the subject and nothing else, and a role in a token is frozen until expiry; deny on failure; an inventory item. An adapter package declares only what is true of it in any domain: whether it requires a ledger, its `scope` cap, its inventory item, its default origination profile, its parameters. The capability declaration per rule, native, limited, or unsupported for each of C1 to C13 with the enforcing component named, lives in the thin application, because it is a claim about this domain on this adapter. **Revocation latency** is evidence, not a declaration: a Tier 1 case per adapter on the committed repo measures the time from a revoking write's commit to the first denied check, decomposed into commit, projector drain, policy propagation, replica lag, and cache, with components the test environment lacks printed "not measured"; the statement compares the number with the FedRAMP-assigned PS-4 value ⟨verify⟩, and no test asserts it. Every adapter's decision half reaches the database only through the ledger behaviour and `around_query/3`; its `scope` half needs Ecto. Each adapter package ships `priv/conformance/`, the artifacts Tier 1's neutral fixture needs on that mechanism, so the fixture stays core's and the CUI domain stays out of the adapters. Comparison and notes: `docs/reference.md` §4.

## The line

Opinionated below the port, neutral above it.

Below: Ecto is required for the seam and for `turnstile_ledger`, without apology: a seam is the only way a library proves "always invoked," and a ledger the only way it records history. Postgres is the reference database and the only one the suite runs; the ledger's few database-dependent mechanisms live in a dialect module, `Postgres` and `Generic` shipped and no more; the RLS adapter is Postgres. The statement prints the database, the dialect, and `tested` or `untested`.

Above: `authorize`, `check`, `batch`, `explain`, the events, the ledger contract, policy versions, `review` over a population, and the generator reach the database only through the ledger behaviour and `around_query/3`, and a compile-time `boundary` rule keeps `authorize`, `check`, `batch`, `explain`, and `review` off `ecto_sql`.

Two altitude tests; if either needs a change in core, core is too low. *Bring your own adapter*: implement the adapter behaviour, ship a declaration, pass Tier 1, and the generator prints your statement. *Bring your own store, or none*: an event-sourced application on Cerbos or OpenFGA with no Ecto produces a statement, forgoing `scope` and the seam, with mediation, drift, and point-in-time review printed as its own claims. The graph adapter's projector drains that application's event store as readily as the Ecto ledger; nothing below the port is required of it. The second test stays a constraint core is designed to, and the event-store mode that would exercise it is deferred.

What the library makes an adopter use: Ecto for the seam; a Repo module extended by core, because a wrapper breaks every tool that expects a real `Ecto.Repo`, and a second one with the owner role for the library's own writes; Postgres for the tested path and for RLS; a Postgres to run Tier 1 against, which the repo's own suite gets from its Nix shell; two Credo checks. Anything beyond that is a request, not a plan.

## The example: controlled unclassified information

CUI is what a federal system protects below the classified line: information a law or regulation says must be safeguarded, marked with its categories, restricted by dissemination controls, decontrolled on a date or an event, governed by 32 CFR Part 2002 and the NARA Registry, and requiring Moderate confidentiality, which is why the baseline. It was chosen because its rules exercise each mechanism differently: a write the database can refuse, a rule a policy team should own, a derived marking a stateless engine cannot compute, an implication a graph walks without copying. And because it is what FedRAMP exists to protect. The word is assessment-ready, never compliant.

```
Agency ──< Office(designating) ──< Program ──< Assignment(user, role: lead | member)
Office  ──< OfficeRole(user, role: designator | approver)
Program ──< Document(designated_by: Office, marking: Marking, decontrol: date | event | nil)
Document ──< Portion(marking: Marking)
Marking  = (categories: [Category], controls: [Control], list: [User])
Category(name, specified?: bool, implied_controls: [Control])
Control  : federal_only | no_foreign | named_list | releasable_to([country])
User(employment: federal | contractor, nationality)
```

The Agency is the tenant. Access is by lawful government purpose, modeled as assignment to a program (C1). Dissemination controls narrow it below that default; four are modeled, one per shape of test on the subject (an attribute equals a value, FED ONLY; matches the designating agency's, NOFORN; is in the object's list, REL TO; or the subject is on a per-document list, DL ONLY) and all must hold (C2); the rest of the Registry are the same four shapes with other values. Specified categories imply controls, computed and never copied (C3). A document is portion-marked: each Portion carries its own marking and the document's banner is the union of its portions', enforced at write time in the domain (C4); a redacted read returns the document with the portions the subject may not read removed, built as a Document decision plus a Portion `scope`, and scope fidelity (C13) holds at portion level, so each adapter filters portions as their own rows under their own policy. Decontrol ends the controls but never the lawful-purpose rule (C5). A marking change needs a designator (C7), a fresh re-authentication (C8), and a different approver (C9). A privileged user may read past C1 with a justification that is logged and reported, never unconditionally (C10). Everything is evaluated at every check (C11), enforced within the revocation clock (C12), and `scope` returns exactly what `check` allows (C13). Training is a procedure the organization evidences (AT-3), not a fact the library checks. Lists show titles and banners under `scope`; opening a document is a per-object read. Full tables: `docs/reference.md` §2 to §3.

Document, Portion, Program, Assignment, OfficeRole, and Marking declare object types and are protected; lookup tables such as Category and Country declare none and pass the seam without a decision. The fact mapping is the domain's own: Assignment and OfficeRole rows are relationships with a role attribute; a Marking's controls and list are set-valued and emit one event per element; employment and nationality are subject attributes; a Document's marking and decontrol and a Portion's marking are object attributes. The domain, its contexts, its web layer, and every scenario live in `turnstile_example`, a library application; `example_code`, `example_postgres`, `example_cerbos`, and `example_fga` each bind one adapter to it and add only what that adapter needs.

## Evidence

A **scenario** is a test whose name is a sentence, citing a control in the Moderate baseline or a KSI (marked when it cites beyond the baseline), and the lint checks every citation against the pinned sources. Scenarios every adapter passes identically are kept, because a buyer checks them off; parameters a control leaves open are configuration the scenario reads, never constants in a rule. Groups follow what a 3PAO examines: enforcement, least privilege, separation of duties, revocation and expiry, decision audit, access review, re-authentication, emergency override, change control on policy, inventory (ids: `docs/reference.md` §1). The scenario table (id, sentence, group, controls cited, the rule it tests) is written before code and frozen with the contracts.

Two tiers. **Tier 1**, in core, proves the port's guarantees, the seam, and the ledger over a neutral fixture, on Postgres and nothing else, with shape tests (query, record, and row counts, stated per adapter and per ledger mode) checked but not cited, and three projection cases (measured lag, drift from an out-of-band write, convergence of a re-drain) that activate only for an adapter that declares a projection and run on the committed repo; any adapter that passes earns a statement with no example work. **Tier 2** is the CUI scenarios, run once per thin application. A run reports how many scenarios executed, and CI fails on a count of zero, or on a skip that names no declared capability, or, in a mode-none run, no need for a ledger: a suite that passes by skipping proves nothing.

`mix turnstile.assess` folds declarations, results, configuration, and the pinned sources into, per control: the control implementation statement and its implementation status; **origination**, in the SSP's own values, defaulted per adapter and declared by the provider, because the SSP is theirs; the **responsibility split** (library implements, application must, organization must), which is a different axis from origination and becomes the CRM; parameters, FedRAMP-assigned apart from provider-chosen; the evidence, meaning scenarios and results, commit, date, versions, latency and its components, ledger mode, database and dialect, pinned-source versions; the seam's surface and exemptions; inventory items; and a POA&M row for every rule the thin application declares unsupported, saying what would close it. A rule enforced by another component of the same stack is native, with that component named, and "not applicable" earns no row. Results arrive from an ExUnit formatter that writes `results.json` per run: scenario id, outcome, skip reason, capability, latency measurements. The statement is two files per thin application: `statement.md`, deterministic and committed, regenerated and diffed by CI on every pull request; and `evidence.json`, volatile (commit, date, versions, latency, run id), regenerated beside it and never diffed. One profile in the first implementation: **Rev 5**, as markdown. The OSCAL component definition, the 20x profile, and `--diff` are on the deferred list, each with what brings it back. `mix turnstile.review` prints who can do what, today or, with a ledger, on a date.

The library does not claim authorization status, own identity, own the audit store, decide origination, or promise portability it has not tested.

## Packages and conventions

```
turnstile/
  PLAN.md · CLAUDE.md · README.md · flake.nix · flake.lock · .envrc
  docs/        reference.md · testing.md · code.md · delivery.md · writing.md · glossary-index.md
  apps/
    turnstile_core/       port, structs, clock, ledger and projection behaviours, the seam (surface
                          classification, fact-recording hook, around_query), Credo checks,
                          the top-layer boundary rule, AdapterCase, the fake adapter, the in-memory
                          ledger, test cluster support; depends on ecto, not ecto_sql
    turnstile_ledger/     the Ecto ledger: counter row, events table, migration and genesis helpers,
                          the catalog check, bulk fact API, dialects Postgres and Generic, reconcile,
                          replay; ecto_sql
    turnstile_code/       rules in code: declared roles and permissions, attribute predicates;
                          priv/conformance/
    turnstile_postgres/   row-level security, session settings through around_query, check for writes,
                          policy versions from migrations; priv/conformance/
    turnstile_cerbos/     attribute declarations, query plan to dynamic, policy versions, decision-log
                          reconciliation; priv/conformance/
    turnstile_fga/        tuple mapping behaviour, the client behaviour and its fake, projector with
                          checkpoint and rebuild, the checkpoint migration helper, Check/BatchCheck/
                          ListObjects/Expand behind the port, model publication as policy version;
                          priv/conformance/
    turnstile_assess/     the generator (Rev 5 markdown); the ExUnit formatter and results.json; the
                          lint; priv/sources.exs and the pinned sources; mix turnstile.assess and
                          mix turnstile.review
    turnstile_example/    a library app with no application callback: the CUI schemas, Portion included,
                          object-type and fact-mapping declarations, contexts, the redacted read, the
                          hash-chained audit store, Example.Repo and Example.OwnerRepo, the router,
                          controllers, the identity-only plug, fixtures, Example.Migrations.Domain, and
                          every scenario as test support (Example.Scenarios)
    example_code/         the thin apps, each with its own config and Application.start/2: the adapter
    example_postgres/     binding, the per-rule capability declaration, policies (cerbos), model and
    example_cerbos/       tuple mapping (fga), RLS policies and write gates (postgres), priv/repo/
    example_fga/          migrations, priv/schema/<adapter>.sql, statement/, a test file that runs
                          Example.Scenarios under this adapter, a README with the translation table
```

Twelve apps: eight library packages with the `turnstile_` prefix and four thin applications without it. Migrations: library packages ship migration helpers; migrations exist only in the thin applications, one set each. `turnstile_example` ships the domain tables as a helper the thin application's first migration calls; `turnstile_ledger` ships the counter, events, and genesis helpers; `turnstile_fga` the checkpoint helper; `example_postgres` writes its RLS migrations by hand, since they are the teaching artifact. Each thin application's CI job dumps the schema after migrating and fails on a diff against the committed file, because that diff is what proves the teaching artifact; `example_code` runs Tier 2 twice, once per ledger mode, so mode none has a real run.

Engineering: Elixir 1.20.4 on OTP 29.0.6, with every type warning an error and no Dialyzer; the adapter bound at boot from `%Turnstile.Config{}`, validated once from a NimbleOptions schema as the only runtime configuration the library reads, so one build serves every adapter and Tier 1 binds per test module; a Nix flake locked to `nixos-unstable` pins Elixir, OTP, Postgres 18, OpenFGA 1.19.0 from nixpkgs, and Cerbos 0.55.0 fetched from its release archive, and is the only documented path for development and CI: no Docker, no `.tool-versions`; `boundary` in core for the top-layer rule. Testing: every test owns its state, an ephemeral Postgres per run, `async: true` by default, and every fake returns a value of the real type rather than raising, so the type checker does not read a stub as a certain crash (`docs/testing.md`, `docs/code.md`). The conformance mechanisms (the scenario macro, the lint that reads test files without compiling them, the unknown-scenario check, the property seed) ship in core and in `turnstile_assess`.

Documentation: the tree above holds these files and no others at the top level; one glossary per bounded context, colocated with its package, translations at boundaries, with `docs/glossary-index.md` naming every word that carries more than one meaning and the one place each meaning lives, and each thin application's README carrying a translation table from the domain's words to the adapter's; the assessment context's glossary is FedRAMP's vocabulary, and its boundary is where the engineers' words become the 3PAO's; foreign concepts get two sentences and a link; the banned-words lint, which also enforces the two reserved words; test names are the scenario sentences.

## Phases

Thirteen stages, S0 to S12, each with a mechanical gate, run in sequence on one branch. The detail, every gate as a command and its expected output, is `docs/delivery.md`. There is one pause, after this plan and its companions, for the owner to read and approve; after it the stages run to completion, each gated, reporting at the end or when blocked.

- **S0. Toolchain.** The flake, the ephemeral cluster, CI; the gate prints the pinned Cerbos and OpenFGA versions from the packaged binaries.
- **S1. Contracts.** The port, the structs, the ledger and projection behaviours, the matching rules, the fact payload and its macro, the exemption struct, `around_query/3`, the configuration schema, the scenario table, the conformance modules; the frozen interfaces.
- **S2. Core mechanisms.** The seam with its after-compile check and the upsert refusal; the fake adapter, the in-memory ledger, Tier 1 with the latency case template; the generator skeleton with the formatter and the skip check.
- **S3. The example.** `turnstile_example` and `example_code`, the seam enforcing from the first commit; the role table, the override, re-authentication, and `review` land here and in S4. First real statement, ledger mode none.
- **S4. Rules in code.** `turnstile_code`.
- **S6. The ledger.** One shard around the counter row: table, helpers, genesis, the bulk API, both dialects, the reader, reconcile, replay, the catalog check, the interleaving and lock-cost cases.
- **S7. History.** `example_code` in ledger mode Ecto: fact fields through the macro, the genesis migration, the history scenarios; mode none stays a second Tier 2 job.
- **S8, S9, S10. Postgres, Cerbos, OpenFGA.** Adapter package, then thin application, in sequence; S10 builds the client behaviour and its fake before the projector.
- **S11. Point-in-time review**, drift scenarios, replay for all four adapters, including the throwaway graph.
- **S12. The README** with the four statement bodies, the schema dumps, the statement diff jobs.

## Decisions, each with the alternative it rejected

- FedRAMP on two tracks over one catalog, 800-53 ids as the key; not Rev 5 alone. The first implementation emits the Rev 5 profile and defers the rest.
- The Moderate baseline, because CUI needs it; CUI over the classified domain.
- Rules in code first, because RBAC is the baseline's default and a single role is not RBAC; not RBAC as the lesser adapter.
- Four adapters, named for the mechanism, OpenFGA included as the graph with its boundary cost printed; not leaving it out on that cost, because the example is where a team compares the four and the cost is evidence, not a reason to hide the option.
- Decision events carry an applied position and a head position; an adapter may declare that it requires a ledger; the projection behaviour has a checkpoint and a rebuild: the three amendments the graph exercise found, applied for every adapter. The head is one counted query in ledger mode Ecto and absent in mode none.
- Four admission rules; not hosted engines, which are another system needing their own authorization, not facts in tokens, and not allow-on-timeout.
- Fact events in 800-162's terms, declared column by column through a macro, carrying old and new, the domain mapped at its boundary; not domain-shaped events in core and not table-level facts.
- Ecto in core and `scope` as a `dynamic`; not a filter language of core's own, which guaranteed narrowing and a faithful record but could not express subqueries and cost a language and two compilers; the price is ORM independence, which the port never needed.
- Mediation at the Repo seam, at runtime: a schema protected by declaring an object type and matched by its root source, exemptions per call with a reason, the surface classified after compilation with the overrides asserted in force, a fourth extension point for the adapter; not a compile-time heuristic that could not see writes two calls down, and not hand-listed overrides.
- Two Credo checks for the seam's two blind spots, and no more; not re-deriving statically what the seam proves.
- Revocation latency measured end to end on the committed repo and reported, never asserted; not projection lag, and not a timing gate in CI.
- The ledger optional with two modes, genesis as its origin, append-only by grant, cascades caught in the catalog, the library recording rather than owning; not a fold that writes the application's tables. Authorization facts are event-sourced; the application is not, which is its own choice.
- Policy-version events as dated pointers, content only under a cap; not bundles in the ledger.
- Audit records per operation and ledger rows per fact, with a declared bulk API that skips unchanged rows, old values from a locked re-read, and upserts on fact schemas refused; not per-row audit records and not refusing bulk writes outright.
- A counter row; commit order is position order; not sequence positions with a reader that waits for visibility, which skipped events and made replay to the head inexact. A watermark reader stays a later dialect option.
- The line: opinionated below the port; above it, the database reached only through the ledger behaviour and `around_query/3`, by compile-time boundary; not portable-everything and not Postgres-only.
- The library emits and the example stores, chain anchored in the SIEM; not owning a store.
- Origination declared by the provider; the responsibility split as the CRM's input; not conflating the two.
- Pinned sources with a bump procedure; not hard-coded citations.
- One library application and four thin applications, one statement each, regenerated on every pull request, the adoption guide deferred; not the example built by migration with tags as the guide and a CI diff as the guard, because every encoding of the steps rotted with the generator or forced a rebase cascade.
- The adapter bound at boot from the configuration struct, one build for every adapter, optional callbacks answered at runtime; not `Application.compile_env/3`, which needed a build per adapter and could not run four adapters in one test run.
- Capability declarations per rule in the thin application, three levels with the enforcing component named, only unsupported earning a POA&M row; not in the adapter package, which would carry the domain, and not a fourth level for a cell that was never a rule.
- Portions modeled, the redacted read as a Document decision plus a Portion `scope`, C13 at portion level; not document-level marking alone, which would leave C3 and C4 exercising every mechanism the same way.
- Cerbos derived markings through the `filter` fallback, recorded limited; not materialized, which copies what C3 says is never copied.
- Postgres session settings inside `around_query/3`, `check` for a write as a select of the policy's predicate; not `SET LOCAL` with no place to run.
- The ledger projects into the engine: a checkpoint per acknowledged write, a drain by diff, rebuild into a fresh store, a client behaviour with a fake; not engine-owned facts with an outbox, because the ledger is the assessment's system of record.
- Statements from a results file an ExUnit formatter writes, a deterministic body and a volatile evidence file; not a statement per tag.
- A green suite of skipped scenarios is a failure; not trusting a green run.
- Refusal raises; not an undefined return.
- Each adapter ships `priv/conformance/` for the neutral fixture; not the CUI domain in adapter packages.
- Nix for the toolchain and every service, pinned to versions verified on a date, and an ephemeral Postgres cluster per test run; not Docker Compose and a shared development database.
- Shape tests that count queries, records, and rows, per adapter and per ledger mode, plus one generously bounded tripwire, with benchmarks on demand; not timing budgets in CI, which measure the runner.
- The reasons for each decision in this file, the conformance mechanisms in core and the generator; not a records directory.
- The scenario bar and two tiers; training out; four controls, one per shape; adapter, never FedRAMP's word for the cloud service provider; assessment-ready over compliant.

## Deferred, not deleted

Each returns as its own stage after S12, when its condition holds.

- The OSCAL component definition, never a whole SSP: returns when a customer asks for OSCAL import; validated with the pinned fedramp-automation constraints.
- The 20x KSI output: returns when the pinned 20x docs define a results schema the lint can check.
- `--diff <ref>`: returns when two dated statements of one thin application exist to compare; it reads two `evidence.json` files.
- The event-store ledger mode: returns when an event-sourced adopter appears; the ledger behaviour and the fact event's payload are its contract, so nothing in core changes.
- The adoption guide: returns as educational material after implementation, written from the finished example, never as tags.
