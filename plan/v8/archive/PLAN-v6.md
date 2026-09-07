# Turnstile — plan, v6
*Mode: Explanation* — see the writing conventions below. The rule table, the control table, and the requirement-group table are reference material and move to the example's docs in Phase 2.

*Working name. Decided: the target is FedRAMP on both of its tracks, Rev 5 and 20x, with NIST SP 800-53 Rev. 5 at the Moderate baseline as the one catalog behind both; the example domain is controlled unclassified information (CUI), with the agency as the tenant; the adapters are rules in code, Postgres row-level security, and Cerbos; four dissemination controls are modeled; training is a procedure, not an access fact; the library emits audit records and the example ships the reference store; fact events are defined in SP 800-162's terms and each domain is mapped onto them at its boundary; core depends on Ecto's query library and the port speaks its query vocabulary; `scope` returns an Ecto `dynamic`, so it can only narrow; mediation is enforced at the Repo seam, in core, at runtime; revocation latency, measured end to end, replaces projection lag; the ledger is optional — a behaviour in core with three modes — with a defined origin (genesis) and its record streamed to the SIEM; the example is built by migrating a plain application, tag by tag, and that history is the adoption guide; the catalog, the baseline profile, and the 20x docs are pinned by version; the line is drawn at the port — below it Ecto is required and Postgres is the reference database, above it nothing touches a database. Open decisions are marked ⟨open n⟩ and collected at the end; claims to check against the pinned sources are marked ⟨verify⟩.*

An authorization library for Elixir, built for teams shipping a cloud service that a 3PAO will assess against the FedRAMP Moderate baseline. You keep your authorization mechanism behind a port; the library ships adapters for the mechanisms we would recommend; for each adapter it ships an example application that arrives with its own control implementation statements, its origination and responsibility split, and its test evidence.

The bet: an assessment is passed with evidence, and a library can generate most of it if it owns two things — the history of who was allowed what, and the record of every decision it made.

## Who it is for

The engineering lead at a cloud service provider who has been handed the Moderate baseline and an assessment date. Before they adopt an authorization library they will ask seven questions, and each is a feature of this library, not a paragraph in its README. The control that asks the same question follows each.

1. What happens when a check cannot be made — does it deny? (AC-3)
2. Can I prove every request was checked, not most of them? (AC-3; "always invoked", AC-25)
3. Can I show who can access what today, and who could on a given date last year? (AC-2 account review, AC-6(7))
4. Can I show every decision, and every change to who is allowed what? (AU-2, AU-12, AC-2(4))
5. When I revoke access, how long until it takes effect, and can I prove that number? (AC-2, PS-4)
6. Can I write the control implementation statements without inventing anything? (the SSP)
7. Can my compliance team, and the 3PAO, read what the engineers built? (the SSP and the SAR)

FedRAMP adds an eighth: can I keep producing this evidence — monthly, as Rev 5 continuous monitoring, or quarterly, in a 20x Ongoing Authorization Report — not once. The generator runs in CI, so the answer is the same artifact, dated.

## The words, and how fast they change

Three vocabularies appear in this plan. They change at different speeds, and the package layout keeps each where its speed is harmless.

- **The port's words** — subject, object, operation, environment condition — are NIST SP 800-162's (2014, never revised) and the reference monitor's beneath it. Core, the fact events, and the adapters speak these, and Ecto's query vocabulary, and no compliance vocabulary. They do not move.
- **Control identifiers** — AC-3, AU-2 — are SP 800-53's. A control keeps its number for life, a withdrawn one is never reused, and revisions add: major revisions every four to seven years, patch releases about every two, both additive. Scenarios cite these.
- **FedRAMP's program words** — SSP, control implementation statement, implementation status, origination, POA&M, CRM, parameter, 3PAO, authorization boundary, inventory, continuous monitoring, Key Security Indicator, Ongoing Authorization Report — are changing on a cadence of months at the moment, and their identifiers (KSI ids, impact-level names) are being restandardized. Only `turnstile_assess` uses them, and it reads them from pinned sources rather than carrying them in code.

Three sources are pinned, in one file, `apps/turnstile_assess/priv/sources.exs`: the SP 800-53 catalog release (OSCAL; 5.2.0 at the time of writing), the FedRAMP Rev 5 Moderate baseline profile (OSCAL, from the fedramp-automation repository), and the FedRAMP 20x machine-readable docs release. Bumping a pin is a how-to whose output is the lint's diff: the scenarios whose citations changed, were withdrawn, or gained a KSI. A revision is a dependency bump, not a remodel.

Two words are reserved. *Adapter*, never *provider*: provider is FedRAMP's word for the cloud service provider. *Assessment-ready*, never *compliant*, and never *FedRAMP Ready*, which was a designation.

## The thesis: facts have history, adapters are projections, decisions are events

**Ledger.** Every authorization fact is an append-only event, and current state is a fold over the ledger. Core defines four kinds of fact event, in SP 800-162's words: a subject attribute set or cleared; an object attribute set or cleared; a subject–object relationship granted or revoked; a policy version published. Nothing in core names a program or a marking. The example's assignments, office roles, list memberships, markings, and decontrol dates are mapped, field by field, onto the four kinds by the example's **fact mapping**, and any application maps its own the same way.

**Projections.** Each adapter derives its working state from the facts — the tables, a materialized attribute, a policy file — and the delay between a fact or policy change and the first denied request is one measurable number per adapter: the **revocation latency**, which is the answer to question 5. The Tier 1 suite measures it end to end (write the revocation, poll until deny) and decomposes it: transaction commit, policy propagation, read-replica lag, any per-request cache. The statement compares it with the FedRAMP-assigned PS-4 value ⟨verify⟩.

**Decisions.** Every check emits an event: subject, object, operation, environment facts, verdict, reason, adapter, and the ledger position and policy version in force. Decisions are reads, so they form a second stream beside the ledger.

**Replay.** State at a time plus the policy in force at that time reproduces any decision. That is question 3, and no adapter provides it alone: code keeps nothing, the database keeps nothing without temporal tables, the policy engine versions its rules but not the attributes it was sent.

### On event sourcing

The instinct that an event-sourced system is the only "probably correct" one is right about the administration half of an audit — who was granted what, when, by whom — and that is what the ledger is. It is incomplete in three ways, and the design is shaped by them: decisions are reads and must be emitted separately; the rules need history too, or replay answers yesterday's question with today's policy; and append-only is not tamper-evident, which is a storage property the library can help with but not own. Event-sourcing the whole application is a large, orthogonal decision. This plan event-sources the authorization facts only.

## The ledger: a contract with three modes

The ledger is a behaviour in core, `Turnstile.Ledger`: append a fact event, read fact events in order from a position, report the current position. Everything the library builds on the ledger — drift detection, point-in-time review, the position stamped on every decision event — needs only that contract. Who stores the events depends on the application, and the generator prints which mode is in force.

| Mode | Who owns the facts | What the library does | What the statement can claim |
|---|---|---|---|
| **Event store** — the application is already event-sourced | the application's event store | reads it through the application's fact mapping; appends policy-version events through the same behaviour; needs no Ecto — this is the path for an application without one | replay exact; completeness is the application's claim about its own store |
| **Ecto ledger** — `turnstile_ledger` | the application's tables | records one fact event per changed fact field, in the same transaction as the write, through the mediated Repo, in a library-owned table in the application's repo; begins at genesis; reconciles for drift | no fact without an entry inside the application after genesis; drift from outside detected within the reconcile interval; replay exact after reconcile |
| **None** | the application's tables | nothing | drift detection, point-in-time review, and account-management audit (AC-2(4)) printed "application must"; decision events carry no position |

Revocation latency is measured in every mode; what mode none forgoes is history.

An event-sourced application does not need a separate ledger. Its store already is one, on a condition the library cannot check and the statement says so: every authorization fact must be an event. A fact set outside the stream — a migration, a manual fix — is the same drift the Ecto ledger's reconcile exists to catch, and an event-sourced application has no reconcile unless it writes one.

The Ecto ledger runs on any Ecto repo; the same transaction is its only requirement, and the mediated Repo supplies it. Append-only is enforced by the database: the dialect's migration grants the application role insert and never update or delete on the ledger table, on any SQL database, and the statement prints the grant. A conformance case for the ledger behaviour ships with core, so an implementation over another store can prove itself the way an adapter does.

### Positions

The Ecto ledger's position is a database sequence. Sequences interleave across concurrent transactions and a lower position can commit after a higher one, so a reader that has seen position N has not necessarily seen everything below it. The reader behind projection, reconcile, and replay is therefore a dialect concern: `Turnstile.Ledger.Dialect.Postgres` reads only positions below the oldest position still held by an in-flight transaction — the snapshot `xmin` against each row's transaction id — and `Dialect.Generic` reads behind a fixed lag. The alternative, a single counter row locked by every fact-writing transaction, gives commit-ordered positions at the cost of serializing those transactions; a dialect may choose it where the database serializes writers anyway, or where the safe reader proves troublesome. Tier 1 interleaves two transactions on Postgres and asserts no event is skipped. A bulk write's positions are a range with holes in it, which is why its audit record names the `operation_id` and not only the range.

This settles the two drafts of v3. "The ledger owns the facts" is what an event-sourced application brings; "the tables own the facts" is what the Ecto ledger does. The library does not build a fold that writes the application's tables; that is the application's architecture, not the library's.

### Genesis

An application that adopts the ledger has existing state, so the ledger needs a defined origin. Genesis writes every current fact as an event at position 0, stamped "backfilled from tables on ⟨date⟩ by ⟨migration⟩". Reconcile runs from that point; replay and point-in-time review before it are "not available" by construction; the statement prints the date. The example needs genesis too, at the Phase 3 transition from ledger mode none to the Ecto ledger.

### Where the ledger's record goes

Every fact event, like every decision event, is emitted through telemetry and streamed to the organization's log pipeline and SIEM; that copy is the centralized audit record AU-6 and AU-9 ask for, and it is subject to the SIEM's retention (AU-11). The ledger itself is not: in any mode it is complete for the life of the system, or replay stops being exact. A SIEM is a sink; nothing reads authorization state back from it.

## The port

The shape of a question, with no domain and no engine in it: a **subject** — a user, a non-person entity, or a privileged user — an **object**, an **operation**, and the **environment**: facts about this request that live nowhere else. The port supplies the environment facts only it can know, the current time among them, from a clock behaviour that tests replace; the caller supplies the rest, such as when the session last re-authenticated.

Operations: `authorize` (a verdict with a reason), `check`, `batch`, `scope`, and, derived in core, `review` (who can do what across a population — `scope` once per subject where Ecto is present, `batch` over a supplied population where it is not) and `filter`. `explain` is optional per adapter.

`scope` returns an Ecto **`dynamic`**: a fragment of a where-clause — a boolean expression over the queried row — built at runtime. A `dynamic` can only be attached to a query with `where`, so `scope` can only narrow, by construction and with no compiler to trust; it inspects faithfully, so the decision event carries the expression that was enforced; and it may contain subqueries, so C1 is a membership test against `subquery(...)` with nothing prefetched. Rules in code build it directly; Postgres returns `true`, because the database narrows; Cerbos compiles its query plan to one. Core depends on `ecto`, the query library, and not on `ecto_sql`. A port is independent on the axis being swapped — decision engines — and Ecto's query language is itself an abstraction over several databases; `authorize`, `check`, `batch`, the events, and the ledger behaviour touch no Ecto at all, and a compile-time `boundary` rule in core keeps it that way.

Guarantees the port enforces regardless of adapter, and Tier 1 tests for:

- Deny by default. Missing caller-supplied environment facts deny; an unreachable engine denies with its own reason; nothing raises on the request path except a programming error.
- Every call is evented. There is no way to ask the port a question without a decision event. FedRAMP's AU-2 parameter for web applications names authorization checks among the events that must be logged ⟨verify⟩; this guarantee is that parameter, met.
- Actor kinds are enforced at the seam. The privileged user and the non-person entity have their own paths, and those paths emit their own events, because they are the ones a 3PAO asks about first. A privileged user is a separate account, not a flag on a user account (AC-6(2)).
- Mediation is enforced at the data seam. Core's mediated Repo — the application's own Repo module, extended by core — refuses any Repo call that carries neither a decision nor an explicit exemption — reads through `prepare_query/3`, which is also where the `dynamic` is applied; writes through the overridden `insert`, `update`, `delete` and their `_all` forms — and the Tier 1 suite asserts that every write in a test produced exactly one decision event. Together they are the strongest claim a library can make about "always invoked" (AC-25, beyond baseline), and they are runtime claims, not a static heuristic. An **audit mode** logs unmediated calls instead of refusing them; its output is an adopting application's inventory of what is not yet checked. On the controller surface, actions call generated per-operation functions, so a misspelled operation fails to compile.

The port's vocabulary is SP 800-162's — subject, object, operation, environment condition — so the compliance team's words and the engineers' words are the same words.

### The Repo seam

The mediated Repo is the application's own Repo module with `use Turnstile.Repo` placed after `use Ecto.Repo`; the macro raises at compile time if the order is wrong. The failure mode this design must defend against is silent: a Repo function core forgot to wrap does not raise, it runs unmediated. Two nets, and a static check for what neither can see.

- **Exhaustiveness at compile time.** Core holds the Repo surface as data, `Turnstile.Repo.Surface`: every `Ecto.Repo` function classified as *query* (mediated through `prepare_query/3`: `all`, `one`, `one!`, `get`, `get!`, `get_by`, `get_by!`, `reload`, `reload!`, `aggregate/3` and `/4`, `exists?`, `stream`, `preload`, `update_all`, `delete_all`), *write* (overridden: `insert`, `insert!`, `update`, `update!`, `delete`, `delete!`, `insert_or_update`, `insert_or_update!`, `insert_all`), *raw* (wrapped to demand an exemption: `query`, `query!`, `query_many`, `query_many!`), or *plumbing* (touches no rows: `transaction`, `rollback`, `in_transaction?`, `checkout`, `checked_out?`, `config`, `start_link`, `stop`, `child_spec`, `load`, `get_dynamic_repo`, `put_dynamic_repo`, `default_options`, `prepare_query`, `to_sql`, `explain`, `disconnect_all`, `__adapter__`). In a `@before_compile` hook core reads the module's actual public functions with `Module.definitions_in/1` and fails compilation on any name and arity it has not classified — including the shorter arities that default arguments generate, functions the adapter injects, and the reduced surface of a `read_only` repo. An Ecto release that adds a function fails adopters' builds until core classifies it; core pins `ecto` to the minor range the classification was written against.
- **Mediation is injected last.** The overrides and core's `prepare_query/3` are defined in that same `@before_compile` hook, with `defoverridable` and `super`, so they wrap whatever the application or the adapter defined: an application's own tenancy `prepare_query` still runs, inside ours. Overrides redeclare the default argument (`opts \\ []`) so every arity routes through them. ⟨verify⟩ hook ordering against the adapter's own `@before_compile` on the pinned Ecto: Tier 1 has a case that `query/3` refuses without an exemption; if ordering defeats the wrap on some adapter, the raw bucket falls to the static check alone and the statement says so.
- **Proof at runtime.** A Tier 1 sweep generated from `Repo.__info__(:functions)` calls every non-plumbing function with a fixture and no decision and asserts refusal, so a new function fails the sweep until classified. Explicit cases for the paths people assume are covered: `preload`, `aggregate`, `exists?`, `stream`, `reload`, `insert_all` with entries and with a query source, and an `Ecto.Multi` run through `transaction`, whose operations call the Repo's own functions and must hit the overrides. ⟨verify⟩ that `prepare_query/3` fires for the queries `preload` generates on the pinned Ecto; the case settles it.
- **What the seam cannot see, a static check does.** Core ships two Credo checks. `Turnstile.Credo.NoRawSQL` flags `Ecto.Adapters.SQL.query*` and `Postgrex.*` calls — which bypass the Repo module entirely — outside an allowlist (migrations, reconcile, the ledger's own code). `Turnstile.Credo.UnmediatedRepo` flags any `use Ecto.Repo` without `use Turnstile.Repo`: a second repo added later disables mediation, scope, and fact recording at once, and nothing at runtime notices. Both are advisory in the statement; the claim stays with the seam. Nothing else belongs in Credo — a check that every Repo call carries options is the v5 heuristic reborn, and module-dependency boundaries are the `boundary` library's job, which core already uses for its own top layer.

The statement prints the surface classification with counts, the Ecto version, a hash of the surface, the exemption list with reasons, and the static-check results.

## Audit: the library emits, the example stores

The library is an authorization library. It emits two streams — fact events and decision events — through telemetry, with the content AU-3 requires of an audit record: event type, time, source component, outcome, the identity of the subject, and a request or session identifier for correlation (AU-3(1)). Decision events carry the verdict, the reason, the adapter, the policy version, and the ledger position; they do not carry attribute values by default — the position is what replay needs, and nationality does not belong in a log stream.

### Record shapes

The decision for a collection operation is a rule, not a list of rows; the rows are an outcome. Four operations, two shapes:

- `authorize` and `check`: one record per object — subject, object type and id, operation, verdict, reason.
- `batch`, and the derived `filter`: one record for N objects with N verdicts; ids listed up to `batch_ids_cap`, beyond it a count and a SHA-256 of the sorted ids. Never N records.
- `scope`: one record naming the object type, the operation, and the enforced rule — the inspected `dynamic`, truncated at `rule_cap` with a hash of the full text, parameter lists longer than `batch_ids_cap` elided to a count and a hash — with the ledger position and policy version stamped. Replay recomputes the row set from the position and the rule; the record never stores it.
- `review`: one record per review, not one per subject.

Where "who read document D" must be answerable, that is a single-object `read`, and the example makes opening a document one: lists show titles and banners under `scope`; the content is an `authorize` on the document, which is also where C8 and C10 attach. The statement says, under AU-3, that a collection read identifies its objects by type, rule, and count.

### The span

Every port call is a telemetry span at the Repo seam, which sees both sides of a query: `:start` carries the decision at the moment it was made, with its ledger position; `:stop` carries the outcome — rows returned, rows affected, the `operation_id`, duration; `:exception` carries the failure. A query that errors or a process that dies still leaves the decision on record, which is what AU-2's "successful and unsuccessful" asks for. The position is stamped at decision time and the query runs in the same request: a `dynamic` built from prefetched subject attributes is as fresh as the decision, one built on subqueries is as fresh as execution, and either gap sits inside the measured revocation latency; Postgres row-level security evaluates at execution.

### Bulk writes, fact fields, and the ledger

The invariant: the ledger grows with what changed, not with what ran.

- **Fact declarations name fields.** A fact schema declares which columns are authorization facts — `role`, `revoked_at`, `nationality` — and the fact mapping applies to those columns only. A single-row write emits one fact event per changed fact field; Ecto changesets already carry only actual changes, so a no-op write emits nothing. A bulk write whose `set` or `inc` touches no fact field emits no fact events: one decision record, outcome count, and no `RETURNING` requested. Most bookkeeping jobs end here.
- **Bulk writes to fact fields go through a declared API.** Plain `update_all`, `delete_all`, and `insert_all` against a fact schema's fact fields are refused by the seam when the configured ledger asks for it — the Ecto ledger does; event-store mode and mode none do not — with a pointer to `turnstile_ledger`'s `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, and `bulk_insert/3`, because a mass change of authorization facts should be deliberate, and because the API can do what `update_all` cannot: for every field it sets, `bulk_update` adds a null-safe "is different" condition in plain Ecto — `is_nil(field) or field != ^value`, or `not is_nil(field)` when the value is nil; no fragment, so it is portable — and a sync that rewrites a million rows emits facts only for the rows whose value changed. Computed sets — `inc`, fragments — cannot be compared in advance and record every affected row, which is correct. The bulk API needs the affected rows back, and how it gets them is the dialect's answer: where the database can return them (`RETURNING` on Postgres) it asks for ids, and the deleted rows for deletes; otherwise it selects the ids first, under the dialect's lock clause, in the same transaction, then writes.
- **Ledger per row, in batches, in the transaction.** A bulk write that changes twenty thousand facts writes twenty thousand fact events, because replay needs each, inserted with `insert_all` in batches of `fact_insert_batch` rows — a dialect default — inside the same transaction as the write. Every fact event carries the `operation_id` of the decision that produced it, indexed.
- **Telemetry per operation.** The default handler emits one record per operation, never per row: the decision, the count, the `operation_id`, and the minimum and maximum ledger positions the facts landed in. An investigator pulls the rows by `operation_id`; the SIEM gets "a job revoked 20,000 assignments at 02:00," which is the better detection record. The example's chained store writes one chained record per operation for the same reason.
- **A smell to watch.** A job that flips a million authorization facts nightly is a modeling error before it is a ledger problem: something bookkeeping-shaped has been declared a fact. The field-level declaration is where it is caught.

### Volume, caps, and budgets

Emission is total: every port call emits. Forwarding is configured: `decision_volume` is `:all` (the default) or `:denials_writes_privileged`; denials, writes, and privileged operations are always forwarded and never sampled; the statement prints the setting. Caps are configured parameters with defaults and appear in the statement: `batch_ids_cap` 1,000; `rule_cap` 4 KB; `policy_content_cap` 64 KB; `fact_insert_batch`, a dialect default — 2,000 on Postgres against its limit of 65,535 bound parameters per statement, a few hundred where a database allows fewer.

Numbers to plan against. Tier 1 checks the budgets among them, as budgets — they cite no control and are not evidence.

- A decision record is the size of an access-log line, 300–600 bytes. At `:all`, a service making 1,000 port calls per second produces about 86 million records a day, tens of gigabytes uncompressed. That is a log-pipeline sizing question, not a ledger one, and it is why `decision_volume` exists.
- A fact event row is 200–400 bytes; a million fact changes a year is a few hundred megabytes. Retention is the life of the system; partition the table by position range if growth demands it — the read-from-position contract does not care.
- Seam overhead on a single-row operation: budget 200 µs median above unmediated Ecto, excluding the ledger insert, which is one more row in the same transaction.
- A 100,000-row bookkeeping `update_all` on a fact schema touching no fact field: one decision record, zero fact events, overhead under 5% of the unmediated time.
- A `bulk_update` changing a fact field on 20,000 rows: 20,000 fact events, one telemetry record, under two seconds on the docker-compose Postgres.
- A `bulk_update` setting a fact field to its current value on 1,000,000 rows: zero fact events.
- A scoped `all` returning 10,000 rows: one decision record and no per-row cost.

The library ships an attachable default handler that writes both streams to the application's logger, from which the organization's log pipeline carries them to its SIEM. It does not own a store.

The example does: an append-only table with hash chaining, written by the default handler, with a verification task that walks the chain. The chain head travels in every emitted event, so the SIEM's copy anchors the chain and verification compares the two; a chain that lives only in the database it protects can be rewritten by whoever can write that database. The store is there so the statement's "application must" line for audit has a working reference behind it, and so the point-in-time review in Phase 5 has something to replay from. It is documented as the example's, and a team may replace it with whatever their log pipeline already is.

## Adapters

Three, chosen by how well each answers the seven questions and by what each costs inside a FedRAMP authorization boundary, where every engine is an inventory item with its own scanning, hardening, validated cryptography, and controls to answer for.

| Adapter | Package | Enforcement | Explains | Revocation latency | Rules live in | Boundary cost |
|---|---|---|---|---|---|---|
| Rules in code | `turnstile_code` | the application's discipline, backed by the mediated Repo | the clause | one request | Elixir modules; a deploy is a policy version | none |
| Postgres row-level security | `turnstile_postgres` | the database; write gates need no application code | verdict only | one transaction | migrations; a migration is a policy version | none new |
| Cerbos (policy engine) | `turnstile_cerbos` | the application's discipline; policies versioned and tested as their own artifact | verdict and matched rule | one request for facts; the policy poll interval for rules | policy files; a policy owner | one sidecar |

**Rules in code is first because RBAC is what the baseline expects.** SP 800-53 is mechanism-agnostic: AC-2(7), in the Moderate baseline, administers privileged accounts under a role-based or an attribute-based scheme, and AC-3(7) is the role-based enhancement. What fails assessment is a *single* role — authentication wearing an authorization hat — because AC-5 and the AC-6 family need at least two. `turnstile_code` holds its role→permission table as declared data, enumerable at runtime, so AC-6(7) review and the statement can be generated from it; the rules that roles cannot express (nationality, employment, dates) are attribute predicates in the same modules. It is named for where the rules live; RBAC is the model it expresses first, and the README says so where an adopter will search for the word.

Rules in code and Postgres are the recommended pair; Cerbos is for teams whose rules are owned by people who do not ship code. A relationship graph (OpenFGA) was considered and dropped: not disqualified, but it adds a server and a second datastore holding copies of the authorization facts, and its strengths — deep relationships, path explanations — matter least in a domain of programs, lists, controls, and dates. The ledger and projection behaviours leave room for it later.

### Admission rules for any adapter

- **Self-hosted only.** The engine runs inside the authorization boundary. A hosted engine is an external service that needs its own authorization or an interconnection agreement, and the library does not ship an adapter for one.
- **No facts in tokens.** A role or attribute carried in a token is frozen until expiry, so revocation and continuous evaluation cannot be enforced. The identity provider contributes the subject and nothing else.
- **Deny on failure.** An adapter that cannot reach its engine answers deny with its own reason. No client default of allow-on-timeout survives the adapter.
- **An inventory item.** Name, version, where it runs, and its own log location, printed by the generator for the Integrated Inventory Workbook (CM-8).

Every adapter declares the same things: a capability per scenario (native, limited, unsupported), a default origination profile, the parameters it exposes, its measured revocation latency, and its inventory item.

### Adapter notes

Every adapter's decision half — `authorize`, `check`, `batch`, `explain` — is database-free; its `scope` half returns a `dynamic` and needs Ecto.

**Where the rules live, and what a policy-version event carries.** The ledger never holds a rule; it holds a dated pointer to one. Every policy-version event has the same small shape — adapter, version identifier, content hash, when, and the author or approval it came from — and it carries the rule's content by value only when that content is text under a configured cap (64 KB by default). Above the cap, or for anything that is not text, it carries the hash and a pointer into the store, and the statement prints which. Decision events reference the version by identifier and never carry content: the rare event holds the bytes, the frequent one holds a key. One event per version, never per node or per boot.

- **Rules in code.** The rules are Elixir modules in the application's repository, compiled into the release. Version: the commit. The application appends the event at boot only when the ledger head names an older version, carrying the commit, a hash of the rule modules, and the role→permission table as data when it is under the cap. The attribute predicates stay in git, so replaying them needs that commit, and the statement says replay of code rules depends on the repository's retention.
- **Postgres.** The rules are policies in migration files, live in the database catalog once applied. Version: the migration number. The migration appends the event in the same transaction as its DDL, carrying the `USING` and `WITH CHECK` expressions read back from `pg_policy` — small text, so replay is self-contained. The application role must not own the tables, or row-level security is bypassed; `FORCE ROW LEVEL SECURITY` on every protected table; session settings set inside each transaction, because of connection pooling; reads from a replica add replica lag to the revocation latency, and the adapter measures it.
- **Cerbos.** The rules are YAML files in a policy repository, loaded into the sidecar's memory from a store it polls. Version: the policy repository's commit; Cerbos's own `version` field on a policy is for running variants side by side, not history. The policy repository's CI appends the event on merge, carrying the commit, a hash of the files, and the files themselves when under the cap. A sidecar picking the version up is measured as policy propagation latency, not ledgered, so a fleet of sidecars adds no events. Facts arrive with each request, so their latency is one request; rules arrive on the poll interval, and that interval is the latency for policy changes. The sidecar's decision logs are reconciled with the port's decision events, and any difference is a drift scenario.

## The example: controlled unclassified information

One application, compiled once per adapter — the adapter is bound at compile time — and each build produces its own statement and evidence. The word is **assessment-ready**, never "compliant."

CUI is what a federal system protects below the classified line: information a law or regulation says must be safeguarded, marked with its **categories**, restricted by **dissemination controls**, and **decontrolled** on a date or an event. Access is by **lawful government purpose**, modeled here as assignment to a program. The marking rules come from 32 CFR Part 2002 and the NARA CUI Registry. CUI training is required of every holder (AT-3), and it is a procedure the organization evidences, not a fact the library checks. The Agency is the **tenant**: the multi-tenant separation question a 3PAO asks is answered by C1 and C13 across agencies.

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

### Dissemination controls

A category says what the information is; a control says who may not receive it, below the default that anyone with a lawful government purpose may. The registry allows a fixed set; a document may carry several; all must hold. Four are modeled, one per shape of subject test:

| Control | Registry marking | Test on the subject |
|---|---|---|
| `federal_only` | FED ONLY | employment is federal |
| `no_foreign` | NOFORN | nationality matches the designating agency's |
| `named_list` | DL ONLY | the subject is on the marking's list — a per-object grant |
| `releasable_to` | REL TO | nationality is in the marking's country list |

The rest of the registry (FEDCON, NOCON, DISPLAY ONLY, the attorney markings) are variants of these four shapes and are left out; each would be one more row, not one more mechanism.

### Rules (draft; moves to the example's glossary)

| Rule | Statement |
|---|---|
| **C1 Lawful purpose** | `read` on a Document requires an Assignment to its Program or an OfficeRole in its designating Office. |
| **C2 Controls, all of** | Every Control on the effective marking is a test on the subject, and all must pass. |
| **C3 Specified categories** | A Specified category adds its implied Controls. Effective controls are declared ∪ implied. Nothing is copied. |
| **C4 Banner** | With portion marking, a Document's marking is the union of its Portions'. ⟨open 1⟩ |
| **C5 Decontrol** | After the decontrol date or event, C2–C4 no longer apply; C1 still does. The current time is a port-supplied environment fact. |
| **C6 Named list is a direct grant** | `named_list` membership is per Document per User and combines with nothing; it never overrides C1. |
| **C7 Marking gates** | Changing a marking, setting a decontrol, or decontrolling requires a `designator` role in the designating Office. |
| **C8 Re-authentication** | C7 operations additionally require the session to have re-authenticated within a configured window. |
| **C9 Separation of duties** | A marking change proposed by one designator must be approved by a different approver. |
| **C10 Audited override** | A privileged user holding the override permission may read a Document outside C1 with a justification; the read succeeds, always emits its own event, and is reported to the designating Office. Never unconditional. |
| **C11 Continuous evaluation** | Assignments, list membership, employment, and nationality are evaluated at every check; a change deletes nothing. |
| **C12 Revocation clock** | A revoked fact is enforced within the configured maximum delay; the adapter's measured revocation latency must be below it. |
| **C13 Scope fidelity** | `scope` returns exactly the rows for which `check` is true. |

### Where the three adapters differ

With three adapters the capability table is mostly native; all three read a clock, test all-of, and look up a list. The differences are in the origination profile, which is the point:

- Write gates without application code — Postgres only: a marking change that violates C7 is refused by the database whether or not the application asked.
- Rules owned by non-developers, versioned and tested as their own artifact — Cerbos only.
- Explanation — Cerbos names the matched rule, code names the clause, Postgres names nothing.
- Derived markings (C3, C4) — Cerbos plans `scope` only over attributes it is sent, so effective controls are materialized per Document or `scope` falls back to `filter` and records limited.
- Request-time facts (C5, C8) — native everywhere; Postgres threads them through session settings.

### Requirement groups

Scenarios are grouped by what a 3PAO examines. Each group cites the Moderate baseline controls it evidences; beyond-baseline citations are allowed and marked; each scenario also carries the 20x KSI id it validates, read from the pinned docs. Enhancement membership is ⟨verify⟩ against the pinned profile, and the lint does it permanently.

| Group | Moderate baseline controls | Beyond baseline (cited, marked) | 20x family |
|---|---|---|---|
| Enforcement | AC-3 | AC-25 always invoked; AC-3(7) role-based | KSI-IAM |
| Least privilege | AC-6, AC-6(1), (2), (5), (9), (10); AC-2(7) | | KSI-IAM |
| Separation of duties | AC-5 | | KSI-IAM |
| Revocation and expiry | AC-2, AC-2(1), (2), (3); PS-4, PS-5 | AC-3(8) revocation of authorizations; AC-16 security attributes (markings, decontrol) | KSI-IAM |
| Decision audit | AU-2, AU-3, AU-3(1), AU-12, AC-2(4); AU-9, AU-9(4), AU-11 | | KSI-MLA |
| Access review | AC-2 account review; AC-6(7) | | KSI-IAM |
| Re-authentication | IA-11 | | KSI-IAM |
| Emergency override | AC-6(9), AC-2(2), AU-6 | | KSI-IAM, KSI-MLA |
| Change control on policy | CM-3, CM-5 | | KSI-CMT |
| Inventory | CM-8 | | KSI-PIY |

Change control is a strength to show, not a burden: for rules in code and Postgres a policy version is a commit and a deploy, so the review is the approval, and the scenario asserts that every policy-version event names its author and its approval.

## What earns a scenario

The bar is "a control in the Moderate baseline, or a KSI, names it," with "an adapter differs on it" second. Each scenario cites a control id and a KSI id; the lint checks the control against the pinned catalog, its baseline membership against the pinned profile, and the KSI against the pinned 20x docs. Scenarios every adapter passes identically are in, because a buyer checks them off. Parameters a control leaves open are configuration the scenario reads, never constants in a rule.

### Two tiers

- **Tier 1, in core, domain-neutral.** The port guarantees over a minimal fixture — two object types, two roles, one attribute, one relationship, as Ecto schemas in a sandboxed test Repo on the docker-compose Postgres: deny by default, every call evented, actor kinds enforced, scope fidelity, deny on engine failure, revocation latency measured, exactly one decision per write; the Repo sweep and the query-path cases from the seam section; the interleaved-transactions case for the ledger reader; the top-layer boundary check; and the performance budgets from the audit section, checked but not cited. The port cases need no database; the seam and ledger cases run on Postgres and on nothing else, so Postgres is the only database the statement calls tested. Any adapter that passes earns a Tier 1 statement with no example work.
- **Tier 2, in the example, per adapter.** The requirement scenarios over CUI.

## The generator

`mix turnstile.assess` ⟨open 2⟩ reads the adapter declarations, the application's declaration, the scenario results, the configuration, and the pinned sources, and prints, per control:

- the control implementation statement, with its implementation status — Implemented, Partially Implemented, Planned, Alternative Implementation, Not Applicable — and which component implements it;
- **control origination**, in the SSP's values verbatim — Service Provider Corporate, Service Provider System Specific, Service Provider Hybrid, Configured by Customer, Provided by Customer, Shared, Inherited from pre-existing authorization — defaulted per adapter and overridden by the application's declaration, because origination is the provider's claim and the library can only default it. The example's defaults: programs, lists, and designators an agency sets → Configured by Customer; CUI training → Service Provider Corporate; everything the library or application implements → Service Provider System Specific;
- the **responsibility split** — library implements, application must, organization must — a different axis from origination, which becomes the rows of the Customer Responsibility Matrix;
- the parameters in force, separating FedRAMP-assigned values from those the provider chose;
- the evidence: scenario ids and results, commit, date, adapter and engine versions, measured revocation latency, ledger mode, and the versions of the pinned sources;
- the seam: the Repo surface classification with counts, the Ecto version and a hash of the surface, the exemption list with reasons, and the static-check results, marked advisory;
- the database: which one, the dialect, the path each dialect-dependent mechanism took, and `tested` or `untested` from the suite's own record;
- the inventory item for each engine;
- a POA&M row for every unsupported cell and every known drift window, in the template's columns — weakness, detection source, remediation plan, scheduled completion, milestones, status — stated plainly, with what would close it.

Two profiles, one declaration set. **Rev 5** prints the statements as markdown and as an OSCAL SSP, with POA&M and CRM. **20x** prints, per KSI, the scenarios that validate it and their latest results, as JSON in the shape the pinned docs define; the conformance suite is the validation code a 3PAO reviews. Which profile a build prints is an input, and so is the impact level.

`mix turnstile.assess --diff <ref>` prints what changed between two statements — cells that moved, latency that moved, POA&M rows opened or closed. It is an adoption's progress and a 20x Ongoing Authorization Report's delta in one command. `mix turnstile.review` prints the account and privilege review (AC-2, AC-6(7)) for today and, once a ledger has history, for a date.

Regenerated on every build, the statement is the continuous-monitoring evidence for the controls it covers.

## Two tracks, one catalog

FedRAMP has two paths to a Moderate authorization. **Rev 5**: a System Security Plan with a control implementation statement per control, assessed by a 3PAO, with monthly continuous-monitoring deliverables; OSCAL is accepted. **20x**: Key Security Indicators — sixty-one for Moderate at the current release — each mapped to SP 800-53 controls, validated by automation the 3PAO reviews, reported quarterly in an Ongoing Authorization Report. Both cite SP 800-53 Rev. 5, so the scenario key is the control identifier, every scenario also carries the KSI it validates, and the generator emits both profiles from one declaration set. Impact-level names are being replaced; the level is an input to the profile and appears in no module or package name.

The Moderate baseline, because CUI is protected at no less than moderate confidentiality. NIST SP 800-171 and CSF 2.0 are mappings onto the same catalog and can ship as profiles later without new scenarios. The port's vocabulary comes from SP 800-162.

## What the library will not claim or own

- **Authorization status.** It produces evidence and statements; a 3PAO assesses and an authorizing official decides.
- **Identity.** Who the subject is comes from the identity provider and nothing else; employment, nationality, and assignments are facts.
- **The audit store.** The library emits; the example stores; protection, retention, and monitoring belong to the system.
- **Origination.** The library defaults it per adapter; the cloud service provider declares it, because the SSP is theirs.
- **Portability it has not tested.** The statement names the database and the dialect; a database the suite has not run against prints `untested`.

## Bring your own adapter, facts, or store

The surface, stated once, and the two altitude tests for core: if any of this needs a change in core, core is too low.

To bring an adapter: implement `Turnstile.Adapter` — `authorize`, `check`, `batch`, `scope` returning a `dynamic`; `explain` optional; ship a declaration — capability per scenario, default origination profile, parameters, inventory item, measured revocation latency; pass Tier 1; optionally implement `Turnstile.Projection` to consume fact events from a position. The generator prints the adapter's statement without a change to core.

To bring facts: implement the fact mapping from the application's schemas' declared fact fields, or its events, to the four fact-event kinds. The mediated Repo records them; the event-store mode reads them; the generator does not care which.

To bring a store, or none: an application without Ecto uses `authorize`, `check`, `batch`, and `explain`; the decision halves of the code and Cerbos adapters; the events and the span; the ledger contract in event-store mode or over its own store; policy-version events; `review` over a supplied population; and the generator. It does not get `scope`, the seam, or `turnstile_ledger`, and the statement prints mediation, drift, and point-in-time review as the application's claims. The test: an event-sourced application on Cerbos with no Ecto produces a statement. Core keeps it true with a compile-time `boundary` rule — the top-layer modules list no Ecto among their dependencies — and the rule is the line the plan draws: opinionated below the port, neutral above it.

## Adopting Turnstile in an existing application

Starting point: Phoenix with Ecto; a JWT whose claim carries one role; a plug that checks it and lets everything else through. Every step ships alone, and every step leaves the application working. Run `mix turnstile.assess` after each; the statement is the progress bar.

| Step | Change | What it earns |
|---|---|---|
| 0 | Add `turnstile_core` and its two Credo checks; run the generator; switch the mediated Repo on in audit mode | The all-red statement, and the audit log as the inventory of unmediated calls |
| 1 | Strip the role claim from the token; a plug resolves roles and attributes per request into the subject | Revocation latency falls from token lifetime to one request — AC-2, PS-4; admission rule "no facts in tokens" |
| 2 | Route the existing check through the port: `turnstile_code`, one role, one permission | Behaviour identical; every request emits a decision; deny by default holds — AC-3, AU-2, AU-12 |
| 3 | Flip the Repo from audit to enforce; clear the step-0 list | Always invoked — AC-3; AC-25 beyond baseline |
| 4 | Declare the role→permission table: a non-privileged and a privileged role at least; security functions under the privileged one; privileged users on separate accounts; every action names its operation | AC-5; AC-6(1), (2), (5), (10) |
| 5 | Apply `scope` to list queries through the Repo seam | Tenant isolation proven — AC-3; C13 |
| 6 | Support and operator access through the audited override: justified, logged, notified | AC-6(9), AC-2(2) |
| 7 | Re-authentication for sensitive operations, from the session's last-authenticated fact | IA-11 |
| 8 | `mix turnstile.review` | AC-2 account review, AC-6(7) — current state |
| 9 | Add `turnstile_ledger`; declare the assignment fields as facts; run genesis | AC-2(4), AU-9; history from the genesis date; point-in-time review |
| 10 | A second layer: Postgres row-level security for write gates and defence in depth, or Cerbos when policy ownership leaves engineering | The origination profile changes; the statement regenerates |

An application without Ecto walks steps 1, 2, 4, 6, 7, and 8 as written; steps 3, 5, 9, and 10 are not available to it, and the statement prints mediation, scope, and history as the application's claims. The event-store ledger mode is how it gets history.

**The example is built by walking this path.** Phase 2 starts from tag `v0-jwt-single-role`, a plain Phoenix application with no Turnstile in it. Each step is a tag; each tag commits its generated statement under `apps/turnstile_example/docs/statements/`; the adoption guide, `docs/how-to/adopt.md`, is the annotated tag list; CI checks out each tag, regenerates, and diffs against the committed statement so the guide cannot rot. The Postgres and Cerbos builds are tags `v10a-postgres` and `v10b-cerbos`. ⟨open 3⟩

## Package layout

```
turnstile/
  PLAN.md · README.md · docker-compose.yml (postgres, cerbos — pinned) · .tool-versions
  docs/        context-map.md · glossary-index.md · references.md · writing.md · adr/
               how-to/adopt.md · how-to/bump-sources.md
  apps/
    turnstile_core/       port, fact and decision event schemas, clock, ledger and projection behaviours,
                          the mediated Repo (mediation, scope application, fact-recording hook, audit mode,
                          surface classification), the Credo checks, the top-layer boundary rule,
                          Tier 1 conformance (adapter, ledger) — depends on ecto, not ecto_sql
    turnstile_ledger/     the Ecto ledger: table and migration, genesis, reconcile, replay, the bulk fact API,
                          dialects (Postgres — reference; Generic — portable fallbacks) — ecto_sql
    turnstile_assess/     the generator: declarations in; SSP (markdown, OSCAL), POA&M, CRM, KSI JSON out;
                          priv/sources.exs and the pinned sources; the lint; review and diff tasks
    turnstile_code/       rules in code: declared roles and permissions, attribute predicates, `dynamic` building
    turnstile_postgres/   row-level security, write gates, session settings
    turnstile_cerbos/     attribute declarations, query plan to `dynamic`, policy versions as fact events,
                          decision-log reconciliation
    turnstile_example/    the CUI application, built by migration from tag v0; Tier 2 scenarios;
                          reference audit store; committed statements; per-adapter notes
```

## Engineering conventions

Elixir 1.20 with its type checker at the strictest setting; no Dialyzer. The adapter is bound at compile time. Docker Compose with pinned tags for Postgres and Cerbos, `.tool-versions` for the rest; Nix is optional and not the documented path. Core ships its own Credo checks and adopters run them; `boundary` is a compile-time dependency of core for the top-layer rule and optional for adopters.

**Databases.** The line: opinionated below the port, neutral above it. Ecto is required for the seam and for `turnstile_ledger`, without apology — it is the only way a library can prove "always invoked" and the only way it can record history. Postgres is the reference database and the only one the suite runs; the statement prints the database, the dialect, the path each dialect-dependent mechanism took, and `untested` for any database the suite has not run against. `turnstile_ledger` ships two dialects, `Postgres` and `Generic`; MySQL and SQL Server dialects are written when someone asks, and the dialect behaviour — batch size, returned rows, reader strategy, lock clause, append-only grant — exists so that the ask costs a small module and a Tier 1 run. The RLS adapter is Postgres by definition. What the library makes an adopter use, in one place: Ecto for the seam; a Repo module extended by core, because a wrapper breaks every tool that expects a real `Ecto.Repo`; Postgres for the tested path and for RLS; Docker Compose for the suite; two Credo checks. Anything beyond that list is a request, not a plan.

## Documentation

The old conventions carry over unchanged: every file declares one Diátaxis mode and stays in it; one glossary per bounded context, colocated with its package, translations at boundaries; decision records kept only where a newcomer would reopen the decision; foreign concepts get two sentences and a link; the banned-words lint; test names are the scenario sentences. `docs/writing.md` returns as it was.

One context is new: **assessment**, owned by `turnstile_assess`. Its glossary is FedRAMP's own vocabulary — control, enhancement, parameter, implementation status, origination, baseline, profile, SSP, SAR, POA&M, CRM, 3PAO, authorization boundary, inventory, continuous monitoring, Key Security Indicator, Ongoing Authorization Report — and the translation at its boundary is the one that matters most, because it is where the engineers' words become the assessor's. The two reserved words, adapter and assessment-ready, are enforced by the lint. The example's per-adapter notes are, as before, the one place the domain's words and an adapter's meet.

### Decision records to write first

The decisions in this plan, each with the alternative it rejected: FedRAMP on two tracks over one catalog, with SP 800-53 control ids as the scenario key; the Moderate baseline; the CUI domain over the classified one; rules in code first, because AC-2(7) and AC-3(7) make RBAC the baseline's default, and a single role is not RBAC; three adapters and the graph rejected on boundary cost; the four admission rules; fact events in SP 800-162's terms, with each domain mapped at its boundary; Ecto in core — the port speaks Ecto's query vocabulary and `scope` returns a `dynamic`, with the rejected filter language recorded beside the three properties it had and how each is kept or paid for; mediation at the Repo seam, in core, at runtime, over a compile-time heuristic; revocation latency, end to end, over projection lag; the ledger as an optional behaviour with three modes, genesis as its origin, policy-version events as dated pointers that carry content only under a cap, the library recording rather than owning, its record streamed to the SIEM; audit records per operation and ledger rows per fact, with field-level fact declarations and a declared bulk API, over refusing bulk writes on fact tables outright; sequence positions with a visibility-safe reader over a serialized counter; the Repo surface classified at compile time with mediation injected last, over hand-listed overrides; two static checks for what the seam cannot see, and no more; the line — opinionated below the port and neutral above it: Ecto required for the seam, Postgres the reference and only tested database, two dialects and no more, the top layer kept database-free by a compile-time boundary — over both a portable-everything design and a Postgres-only one; four controls, one per shape; training out; audit emitted by the library and stored by the example, with the chain anchored in the SIEM; the SSP's origination values and the responsibility split as separate axes; pinned sources and the bump procedure; the example built by migration, tags as the guide, a CI diff as the guard; the scenario bar and its two tiers; adapter over provider.

## Phases

1. **Core.** Port, fact and decision event schemas, clock, ledger and projection behaviours, the mediated Repo with its surface check, the two Credo checks, the top-layer boundary rule, fake adapter, in-memory ledger, Tier 1 conformance on the docker-compose Postgres, budgets included. The generator exists from day one with the pinned sources and the lint, and prints a statement with every control unknown. Glossaries and the first decision records committed before code.
2. **Rules in code and the example.** `turnstile_code`; the example from `v0` through `v8`, tag by tag, with its reference audit store. Enforcement, least privilege, separation of duties, revocation and expiry with latency measured, decision audit, access review of the current state, re-authentication, emergency override, and change control green under rules in code. Rule and control tables move into the example's docs. First real statement, ledger mode none.
3. **`turnstile_ledger`, then Postgres row-level security.** Fact recording through the Repo, the bulk fact API, the `Postgres` and `Generic` dialects, genesis, the reader, reconcile, replay; example `v9`. Then write gates, session settings, append-only enforced by the database role; `v10a`.
4. **Cerbos.** Policy versions as fact events; query plan to `dynamic`; the sidecar's decision logs reconciled with the port's events; `v10b`.
5. **Point-in-time review over the ledger,** drift scenarios, and `--diff`.
6. **Outputs validated:** OSCAL against FedRAMP's templates, KSI JSON against the 20x docs; README with the generated statement for each adapter; the adoption guide as the annotated tag list, with the CI check.

## Open decisions

1. Portion marking: document-level only, or optional portions and the redacted read. Deferred.
2. Names. The library — `Turnstile` is the placeholder throughout — and the assess task. The author will propose them.
3. The adoption guide's form: tags with a CI regeneration check, or the "before" application committed as a fixture directory. Start with tags; decide at the end of Phase 2 from the CI cost.
