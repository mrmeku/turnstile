# Turnstile — a reader's companion to plan v8
*Mode: Explanation. For one reader, who has built multi-tenant RBAC enforced at the query level and wants the rest of the plan to arrive slowly, with its reasons. Nothing here is a decision; the plan holds those. This document exists so the plan reads as obvious.*

## The whole plan in one paragraph

Authorization is deciding whether *this* subject may do *this* operation to *this* object, right now. You already do that: a query scoped to the tenant, and a role check on the way in. The plan keeps that idea and puts three things around it, each because a federal assessment will ask for it. First, a single seam that every check passes through, so "every request was checked" is a fact you can prove rather than a habit you hope holds. Second, memory: every change to who-may-do-what is kept as an append-only event, and every decision is recorded, so you can answer "who could read this document last March, and why" and "how long after I revoked access did it stop working." Third, a generator that turns the tests and the configuration into the documents an assessor reads, on every build. The adapters — rules in code, Postgres row-level security, Cerbos — are three places to compute the decision; the port is the one shape of question they all answer; the CUI example is a domain rich enough to show where they differ.

## How to read this

Fourteen chapters, each standing on the one before. The first five are about the *check* — the thing you already have, generalized. Six through nine are about *memory and time* — what the check has to remember and how fast it has to react. Ten is the example domain. Eleven and twelve are FedRAMP and the generator, which is where all of the above gets turned into paper. Thirteen walks the adoption path from your own application. Fourteen is the list of roads not taken. Two appendices at the end: every term in one table, and a map from plan sections to chapters.

Each chapter has the same shape: the idea, where you have already met it, and what the plan decided and why.

---

## 1. The idea underneath everything: the reference monitor

**The idea.** In 1972 a study for the US Air Force, known as the Anderson report, described what a system needs if it is going to keep untrusted programs away from data they should not touch. It called the thing that checks every access the *reference monitor*, and said the code that implements it — the reference validation mechanism — must have three properties. It must be **always invoked**: there is no path to the data that goes around it. It must be **tamperproof**: nothing outside it can switch it off or change what it does. And it must be **small enough to be verified**: one person can read all of it and test it.

Half a century later this is still the definition of a trustworthy authorization layer, and 800-53 restates it word for word in a control called AC-25, Reference Monitor. Everything in the plan that looks like ceremony — the port, the mediated Repo, the small domain-free core — is one of those three properties being made true.

**Where you have already met it.** Your `where tenant_id = ^tenant.id` is a reference monitor in spirit: the rows a user can see are decided in one place, by one rule. The question the reference monitor asks of it is only the first property. Is it *always* invoked? Every list query, including the one in the CSV export? Every insert — does a user in tenant A ever manage to create a row in tenant B? The report that uses raw SQL? The background job that runs as nobody? In most applications the answer is "almost," and "almost" is exactly what an assessor probes.

**In the plan.** The port (chapter 3) is the one place the question is asked; the mediated Repo (chapter 5) is what makes "always invoked" a runtime guarantee rather than a code-review outcome; core is small and knows no domain so that it can be read whole. Tamperproof is shared with things outside the library — the operating system protects the code, the database enforces row-level security and the append-only role — and the plan says so rather than pretending.

---

## 2. Words for the question: subject, object, operation, environment

**The idea.** NIST SP 800-162, from 2014, is the guide to *attribute-based access control*, ABAC. It gives four words for any access question and they are worth learning once, because the whole plan speaks them.

- A **subject** is who is asking, described by **attributes** — role, department, nationality, clearance, tenant.
- An **object** is what they want to touch, also described by attributes — owner, classification, tenant, creation date.
- An **operation** is what they want to do — read, update, approve, export.
- **Environment conditions** are facts about the moment that belong to neither — the time of day, whether the session recently re-authenticated, where the request came from.

A **policy** is a rule over those four. "A user may read a document if the document's tenant equals the user's tenant and the user's role is at least member" is a policy in exactly this vocabulary.

**Where you have already met it.** Look at that sentence again: it is your system. Your tenant check is an attribute comparison, `object.tenant_id == subject.tenant_id`. Your role check is a subject attribute. You have been doing ABAC with two attributes and calling it RBAC, which is fine, because RBAC *is* ABAC with a single subject attribute called role. This is the reason the port costs you no new concepts. It costs you names.

**The three models, briefly.** RBAC — *role-based access control* — maps users to roles and roles to permissions; NIST formalized it in 1992 and it became an ANSI standard in 2004. ABAC generalizes it to any attribute. ReBAC — *relationship-based* — from Google's 2019 Zanzibar paper and implemented by OpenFGA, stores facts as relationship tuples ("user U is editor of document D," "document D is in folder F") and answers questions by walking the graph. The plan names its adapters by *mechanism* — rules in code, the database, a policy engine — not by model, because each mechanism can express each model well enough, and what actually differs between them is who enforces, who is allowed to change the rules, and what each costs inside a federal boundary.

**Is RBAC good enough for FedRAMP?** Yes, and the catalog says so directly. AC-2(7), which is in the Moderate baseline, tells you to administer privileged accounts under either a role-based or an attribute-based scheme, and AC-3(7) is the catalog's own RBAC enhancement. Most authorized SaaS is tenant-scoped RBAC. What is *not* good enough is a single role, because two controls need more than one: AC-5, separation of duties, and AC-6, least privilege, both of which are about different people being allowed different things. One role is authentication wearing an authorization hat.

**When roles stop being enough.** The sign is *role explosion*: you find yourself creating `tenant_42_regional_approver_emea` because a role is the only knob you have. That is a rule that wants to be an attribute comparison. The CUI example reaches this point immediately — nationality and employment cannot be roles — which is why the code adapter carries attribute predicates alongside its role table.

**In the plan.** The port's question is the four words. The fact events (chapter 6) are defined in the same four words, so nothing in core knows what a "program" or a "marking" is. The code adapter, `turnstile_code`, holds a role→permission table as declared data — because an assessor will ask to see it, and a table can be printed where scattered `if` clauses cannot — plus attribute predicates for the rules roles cannot express.

---

## 3. Where the decision is computed: enforcement points, decision points, and four mechanisms

**The idea.** 800-162 borrows four more words from an older standard, and they name the *places* in an authorization system.

- The **policy enforcement point** (PEP) is where the request is stopped and the answer applied — the plug, the controller, the query.
- The **policy decision point** (PDP) is where the answer is computed.
- The **policy information point** (PIP) is where attributes come from — the users table, the identity provider.
- The **policy administration point** (PAP) is where rules are written and changed.

**Where you have already met it.** In your application the PEP is the plug or the controller action, the PDP is the `if role == :admin`, the PIP is your users and memberships tables, and the PAP is your git repository, because changing a rule means changing code. Every authorization system has all four; what differs is where they live.

**The four mechanisms.** This is the adapters table in the plan, read with the four words:

- **Rules in code.** PEP and PDP are both in the application process; the PAP is git. Enforcement is the application's discipline — nothing outside the process checks that the code called the check. A deploy is a new version of the rules.
- **Postgres row-level security.** The PDP and part of the PEP move into the database: a query that reaches a protected table is filtered whether or not the application remembered to filter it. The PAP is migrations. Writes can be gated without any application code at all.
- **Cerbos.** The PDP becomes a separate process, a *sidecar* — a small server running next to the application — that reads policy files and answers questions over an API. The PEP stays in the application. The PAP is a policy repository that people who do not write Elixir can own, test, and version on their own.
- **OpenFGA.** The PDP is a separate server with its own datastore, and the PIP moves with it: the facts are copied into the graph as *tuples* by a projector that drains the ledger, so the engine holds a copy of who-relates-to-what and answers by walking it. The PAP is a model file, published as an immutable, versioned model. This is the one adapter whose working state is not the application's tables, which is why the plan's ledger has a notion of projection at all (chapter 6).

**Ports and adapters.** The plan uses the vocabulary of hexagonal architecture. A **port** is an interface in core that describes what the application needs — here, the four-word question and the operations on it. An **adapter** is an implementation of that interface for one mechanism. The application talks to the port; the adapter is chosen at compile time. What makes a port real rather than decorative is a **conformance suite**: a set of tests that any adapter must pass to be called an adapter. The contract is the tests, not the type signature. That is why the plan can promise a third party that their adapter gets a generated statement without touching core — the statement is produced from the same tests.

**Where the abstraction stops.** The plan draws one line and defends it. Below the port — `scope`, the mediated Repo, the Ecto ledger — the library is opinionated: Ecto is required, Postgres is the reference and the only database the suite runs, and the ledger's few database-dependent mechanisms live in a small per-database *dialect* module, with a Postgres version and a portable fallback. Above the port — `authorize`, `check`, `batch`, the events, the ledger contract, the generator — nothing touches a database, and a compile-time boundary check keeps it that way. The test the plan uses: an event-sourced application on Cerbos with no Ecto at all can still produce a statement. It gets decisions, events, the ledger contract over its own store, replay, and the generator; it does not get `scope` or the "always invoked" proof, and its statement says so. The reason for the line is where the value is: the FedRAMP-specific parts are the top layer, and the Elixir FedRAMP population is nearly all on Ecto and Postgres, so opinion at the bottom costs almost no one anything.

**Deny by default, fail closed.** Two phrases that mean the same thing from different directions. *Deny by default* means the answer is no unless a rule says yes; a subject with no role, a document with no owner, an operation nobody declared — all no. *Fail closed* means that when the system cannot decide — the engine is unreachable, a required fact is missing — the answer is also no. The opposite, fail open, is how many client libraries ship: a timeout returns "allow" so the product keeps working. The plan's admission rule "deny on failure" exists because an assessor's first question is what happens when the check cannot be made.

**In the plan.** The four admission rules for any adapter now read easily. *Self-hosted only*: the PDP must be inside the authorization boundary (chapter 11), because a hosted decision service is an external system with its own paperwork. *No facts in tokens*: attributes must come from the PIP at request time, not from a token minted an hour ago (chapter 8 explains why). *Deny on failure*: fail closed. *An inventory item*: every engine is a component the boundary must list.

---

## 4. Scoping, generalized: the filter, and why row-level security is different

**The idea.** You enforce at the query level: rather than asking "may this user see document 17?" for each document, you compose a `where` clause so the query only returns what they may see. The plan calls this operation `scope`, and it asks two questions of it. Does `scope` return *exactly* the rows for which a per-row `check` would say yes — no more, no fewer? The plan names that property **scope fidelity** and tests it. And what happens when someone forgets to scope?

**What `scope` returns.** In the plan, `scope` returns an Ecto **`dynamic`**: a fragment of a where-clause — a boolean expression over the row being queried — built at runtime. Something like:

```
dynamic([d], d.tenant_id == ^42 and d.program_id in subquery(my_programs))
```

Two properties make it the right return type. A `dynamic` can only be attached to a query with `where`, so `scope` can only ever *narrow* a query — an adapter cannot widen results or drop a clause, and nothing has to check that it didn't. And it inspects faithfully, printing the expression with its parameters, so the decision event records the filter that was actually enforced. It may contain subqueries, so a rule like C1 — "assigned to the document's program, or holding a role in its designating office" — is a membership test against a subquery, with nothing prefetched. Rules in code build the `dynamic` directly; Cerbos's query-plan API returns a condition tree that the Cerbos adapter compiles into one; Postgres row-level security returns `true`, because the database does the narrowing itself.

An earlier draft of the plan had `scope` return a small filter language of its own, compiled to Ecto by a separate package, so that core would not depend on Ecto. It was dropped. The language guaranteed narrowing and a faithful record, but a `dynamic` gives both without a language to design or a compiler to trust, and the language could not express subqueries. What the change costs is that core now depends on Ecto's query library (`ecto`, not `ecto_sql`) and the port is no longer independent of the ORM — which is acceptable, because a port needs to be independent on the axis you swap, decision engines, and Ecto's query language is already an abstraction over several databases.

**Row-level security.** Postgres has had RLS since 9.5. You enable it per table and write *policies*: a `USING` expression that every row must satisfy to be visible, and a `WITH CHECK` expression that every inserted or updated row must satisfy to be accepted. The database applies them to every query from that role, which is the point: forgetting is impossible, because there is no query path that skips the policy. That is your query scoping moved into the database, where it is always invoked.

Three things about it that the plan spells out because they are easy to get wrong. The database has to be *told who is asking*: the application sets the subject's identity and attributes as session settings inside each transaction (`SET LOCAL`), and policies read them with `current_setting`. It must be inside the transaction because connection pools reuse connections and a setting left behind would leak to the next request. Second, table *owners bypass RLS* by default, and superusers always do; the application's database role must not own the tables, and each protected table gets `FORCE ROW LEVEL SECURITY`. Third, a read from a replica is a read of slightly old data, which becomes part of revocation latency (chapter 8).

**Write gates.** `WITH CHECK` is the part that has no equivalent in application scoping. A rule such as C7 — only a designator in the designating office may change a marking — can be written as a policy, and then a marking change that violates it fails in the database even if the application never asked. That is why the plan's origination profile for Postgres differs from the other two: it can claim enforcement that does not depend on the application's discipline.

**In the plan.** `scope` returns a `dynamic`; the mediated Repo in core applies it; C13 tests fidelity in Tier 1 against Postgres; Postgres row-level security is the recommended second layer behind rules in code because it makes forgetting impossible.

---

## 5. Making "always invoked" true in the application: the Repo seam

**The idea.** In code, forgetting is possible. Version 5 of the plan tried to catch it statically — a compile-time check for controller actions that write without an authorization call — and v6 replaced that, because a static check is a heuristic: it cannot see a write that happens two function calls down, or in a job, or through raw SQL. The runtime approach is simpler and stronger. Every read and write in an Ecto application goes through the Repo. So make the Repo the seam.

**How.** Ecto lets a Repo module override the functions that `use Ecto.Repo` generates, and it calls a hook, `prepare_query/3`, for every query-based operation — `all`, `one`, `update_all`, `delete_all`, `stream`, `exists?` — before it runs. The mediated Repo in core uses both. For queries, `prepare_query` looks for a **decision** in the call's options — the value `authorize` returned — and, finding one, applies its `dynamic` (that is where `scope` happens); finding none and no explicit exemption, it refuses. Changeset-based `insert`, `update`, and `delete` do not pass through `prepare_query`, so those functions are overridden to make the same demand. An **exemption** is a deliberate, named opt-out — `turnstile: {:exempt, "nightly aggregate, no subject"}` — that is logged and listed, so the assessor can see every path that is not checked and why.

**Audit mode and enforce mode.** The same Repo has a mode that logs an unmediated call instead of refusing it. Switch it on in an existing application and the log is a complete inventory of every place a check is missing — which is the adoption path's first step (chapter 13).

**Fact recording.** The seam has a third job. When a write touches a schema the application has declared to be an authorization fact — the memberships table, the markings table — the Repo records the corresponding fact event in the same transaction (chapter 6). The same transaction matters: either both the row and its history are written, or neither.

**The controller surface.** Controllers call generated per-operation functions rather than a generic `authorize(subject, object, :whatever)` — `Authz.read_document/3` exists, `Authz.raed_document/3` does not, and the typo fails to compile. That is the strictness the code adapter adds at the top of the stack; the Repo seam is the strictness at the bottom.

**In the plan.** One seam, three guarantees: always invoked (the refusal), scope fidelity (the filter applied in `prepare_query`), and no fact without an entry (recording in the same transaction). Tier 1 asserts that every write in a test produced exactly one decision event. Mediation moved from Phase 5 into core and Phase 1, because the seam is cheap and the adoption path needs it first.

---

## 6. Facts have history: events, ledgers, folds, and replay

**The idea.** Start with the question your tables cannot answer: *who could read document D on the third of March last year, and why?* A row says who can read it now. To answer for a date you need what changed and when. There are three ways to get that — temporal tables that keep old versions of rows, an audit log written beside the tables, or *events*. The plan chooses events for authorization facts and only for them.

**Events, ledgers, folds.** An **event** is an immutable record that something happened: "assignment granted: user U to program P as member, by admin A, at time t." A **ledger** is an append-only list of events; you add to the end and never change the middle. Current state is a **fold** over the ledger — in Elixir terms, `Enum.reduce(events, %{}, &apply_event/2)` — and state on a date is the same fold stopped at that date. **Replay** is running the fold to a point in time and then asking the question again. This is event sourcing, scoped to one concern.

**Why decisions are kept separately.** A decision — "U asked to read D at t and was allowed, because C1 and C2 held" — is not a fact about who may do what; it is a *use* of those facts. It is a read. If decisions went into the ledger, replaying the ledger would replay the reads. So there are two streams: the ledger of facts and the stream of decisions, and each decision carries the ledger *position* it was made at, so replay can find the exact state it saw.

**Why the rules need history too.** State on a date plus *today's* rules answers the wrong question. If the rule for `no_foreign` changed in June, a March decision must be replayed under the March rule. That is why "policy version published" is one of the four fact kinds: a deploy, a migration, or a policy-repo commit is an event in the ledger like any other. The event is a dated pointer, not the rule: it says which version took effect and when, with a hash, and carries the content itself only when the rule is small text — a policy expression, a YAML file, a role table. The rule's home differs per adapter: the application's repository for rules in code, migration files and the database catalog for Postgres, the policy repository and the sidecar's memory for Cerbos. Replay looks up the version in force on the date, fetches that version's content, and evaluates it over the state folded to the same date.

**The four kinds.** In 800-162's words: a subject attribute set or cleared; an object attribute set or cleared; a relationship between a subject and an object granted or revoked; a policy version published. A **fact mapping** translates an application's own schemas — assignments, list memberships, markings — onto those four. The example ships one; any adopter writes one. Core stays domain-free.

**Three modes.** Not every application wants a ledger, and one kind already has one.

- *Event store.* If the application is already event-sourced, its store *is* the ledger, read through the fact mapping. This is also the path for an application without Ecto. The library cannot check that every fact really is an event, so the statement records that this is the application's own claim.
- *Ecto ledger.* For an ordinary Ecto application, the mediated Repo records a fact event in the same transaction as each declared write, into a library-owned table in the application's own database. The database role that the application uses may insert into that table and never update or delete — append-only enforced by Postgres, not by politeness.
- *None.* The tables are the only truth. Revocation latency can still be measured; what is lost is history — replay, point-in-time review, and automated account-management audit — and the statement prints each as something the application must provide.

**Genesis.** An application that adopts the ledger already has data. Where does history begin? The plan's answer: *genesis*, a backfill that writes every current fact as an event at position zero, stamped with the date and the migration that produced it. Replay before genesis is "not available" by construction, and the statement prints the date. Honest, and an assessor can work with honest.

**Drift and reconcile.** A fact changed outside the seam — a migration that fixes a role by hand, a `psql` session at 2 a.m. — is in the tables and not in the ledger. That is **drift**. **Reconcile** folds the ledger and compares the result with the tables on a schedule; the interval is a number the statement prints, because "drift is detected within N minutes" is a claim the assessor can check.

**What event sourcing buys, and what it does not.** It buys the administration half of an audit: who granted what, when, by whom, and the ability to answer for any date. It does not buy decision history (a separate stream), rule history (policy events), or tamper-evidence (a storage property, chapter 7). And it is only for authorization facts: event-sourcing the whole application is a different, larger decision that the plan explicitly does not make for you.

---

## 7. Two streams, and where they go

**The idea.** An **audit record** is a log entry with a required shape. 800-53's AU-2 asks the organization to decide which events get logged; AU-3 says what each record must contain — what happened, when, where, from what source, with what outcome, and the identity of who or what was involved; AU-3(1) adds correlation details such as a session id. AU-12 says the system must generate them. AU-9 says they must be protected; AU-11, retained; AU-6, reviewed. The plan's two streams — fact events and decision events — are audit records in that shape.

**Emitting.** The library emits both streams through **telemetry**, the Elixir convention where a library publishes named events and the application attaches whatever handlers it likes. The library ships a default handler that writes to the application's Logger. From there the organization's log pipeline carries records to its **SIEM** — a security information and event management system, the central place a security team searches, alerts on, and retains logs. That copy is the "centralized" audit record the catalog asks for. The ledger is not subject to the SIEM's retention; it is complete for the life of the system, because replay needs all of it.

**What a decision event carries, and what it does not.** Verdict, reason, adapter, policy version, ledger position, subject identity, operation, object, a request or session id — and not, by default, the attribute values that were tested. The ledger position is what replay needs, and a person's nationality does not belong in a log stream that a hundred people can search. There is a volume setting: every decision (the default, and the plan flags a FedRAMP parameter that appears to require exactly this for web applications) or denials, writes, and privileged operations only. A `review` across a population emits one event, not one per subject.

**The example's store, and hash chains.** The library does not own an audit store; the example ships a reference one so the "application must" line has something behind it. It is an append-only table with **hash chaining**: each record stores a hash of the previous record's hash plus its own content, so changing any record breaks every hash after it. That is *tamper-evident* — you can detect a change — but not *tamper-proof*: an attacker who can write to the table can recompute the chain from the changed record forward. The fix is to anchor the chain somewhere that attacker cannot reach: the current chain head travels inside every emitted event, so the SIEM's copy holds a record of what the head was, and verification compares the two.

**Collections and bulk writes.** The decision for a list query is a rule, not a list of rows: the record names the object type, the operation, and the enforced `dynamic`, and replay recomputes the rows from the ledger position plus the rule. What happened is recorded after, as an outcome — a count, and for writes the affected ids up to a cap. For bulk writes the plan adds an invariant worth remembering: the ledger grows with what changed, not with what ran. Fact declarations name fields, not tables, so a bookkeeping job that stamps a timestamp on fifty thousand rows emits no fact events; a bulk write that does change fact fields goes through a declared API that skips rows whose value is already the new value, records one fact event per row that changed, and emits one audit record for the whole operation rather than one per row.

**In the plan.** The library emits; the example stores; protection, retention, and monitoring belong to the system. Decision events are minimal by default; the volume is a printed setting; the chain is anchored in the SIEM.

---

## 8. Time: revocation latency, continuous evaluation, and the clock

**The idea.** Authorization has a time dimension that a "does role equal admin" check hides. Three questions expose it. How long after a revocation does access actually stop? Are attributes looked up fresh on each request, or remembered from earlier? And what facts about *this moment* does a rule need?

**Continuous evaluation.** C11 in the example says assignments, list membership, employment, and nationality are evaluated at every check. The alternative — reading them once at login and carrying them in the session or a token — means a revoked user keeps access until the session or token expires. This is the reason for the admission rule *no facts in tokens*. A JSON Web Token is a signed statement minted at login; a role inside it is frozen until the token expires, and nothing the application does later can change what the token says. The token should carry identity — who this is — and nothing else; roles and attributes come from the database on each request. This is also the first step of the adoption path, because it is where your current application is most exposed.

**Revocation latency.** The plan gives the first question a name and a number. *Revocation latency* is the time from a revoking fact or policy change to the first request that is denied because of it. Version 5 called this "projection lag" and measured only one component; v6 measures it end to end — the test suite writes a revocation, then polls the port until it sees a deny, and records the elapsed time — and breaks it into parts: the transaction commit, policy propagation (Cerbos re-reads its policies on a poll interval, so a rule change waits for the next poll), read-replica lag, and any per-request cache. FedRAMP fixes a value for PS-4, Personnel Termination — how quickly access must be disabled when someone leaves — and the statement compares the measured number with it.

**Environment facts, and who supplies them.** Some facts about the moment only the caller can know: when did this session last re-authenticate? Others the port can know itself: what time is it? The plan splits them. The port supplies time from a **clock behaviour** — an interface the tests can replace with a fake, so a decontrol date in 2031 can be tested today — and callers supply only what the port cannot know. Missing caller-supplied facts deny (fail closed); a port-supplied fact cannot be missing. The split exists because of a specific footgun: if `now` were the caller's job, every decontrol check would deny the first time someone forgot to pass it.

**Re-authentication.** IA-11 asks a system to make a user prove it is still them before certain operations — privileged functions, after a period of inactivity. C8 in the example applies it to marking changes: the session's last-authenticated time is an environment fact, and a designator whose session is older than the configured window is refused until they log in again.

---

## 9. Kinds of people: privileged users, non-person entities, and the rules about them

**The idea.** 800-53 does not treat all subjects alike, and neither should the port. Three kinds appear in the plan.

- A **user** is a person with an ordinary account.
- A **non-person entity**, NPE, is software acting on its own — a background job, a service calling another service. It has an identity and it is authorized, but nobody is sitting at a keyboard.
- A **privileged user** is a person who can change the system itself or reach past ordinary rules — an administrator, an operator, a support engineer.

**Least privilege.** AC-6 says each subject gets the least access needed for their job. Its enhancements in the Moderate baseline say, in plain words: explicitly authorize who may use security functions, such as changing roles or markings (AC-6(1)); make privileged people use an ordinary account for ordinary work, which means the privileged identity is a *separate account*, not a flag on the user's account (AC-6(2)); keep privileged accounts to a defined few (AC-6(5)); log every use of a privileged function (AC-6(9)); and make sure ordinary accounts cannot execute privileged functions at all (AC-6(10)). Every one of these is a scenario, and every one is impossible with a single role.

**Separation of duties.** AC-5 says that duties whose combination would let one person do harm are split between people. C9 in the example is the classic form: a marking change proposed by one designator must be approved by a different approver, and the rule enforces "different."

**The audited override.** Sometimes a privileged user must read something the rules would refuse — an incident, a legal hold. Systems call this *break-glass*. The plan's C10 allows it with three conditions: the subject holds a specific override permission, supplies a justification, and the read emits its own event and is reported to the office that designated the document. Never unconditional, because "the operator can read anything" is a finding, while "the operator can read anything with a justification that is logged and reported" is a control.

**In the plan.** The port enforces actor kinds at the seam: privileged users and NPEs go through their own paths and those paths emit their own events, because they are the accounts an assessor asks about first.

---

## 10. The example domain: controlled unclassified information

**Why an example at all.** The library needs a domain to prove itself on, and the domain has to be hard enough to show where the adapters differ — a rule the database can enforce and code cannot, a rule non-developers should own, a derived attribute that a stateless engine cannot compute. It also has to be the kind of data FedRAMP exists to protect, so that the statements are about something real.

**What CUI is.** The US federal government handles a great deal of information that is not classified but still must be protected by law or regulation: personnel records, procurement details, export-controlled technical data, law-enforcement information. In 2010 an executive order gave this sprawl one name, *controlled unclassified information*, and one program, run by the National Archives (NARA). The rule that implements it is 32 CFR Part 2002, and NARA's *CUI Registry* lists every category. A cloud service that holds CUI must protect it at no less than Moderate confidentiality, which is why the plan's baseline is Moderate. The classified world has its own, much larger regime, and the plan deliberately stays below that line.

**The vocabulary.**

- A **category** says what kind of information this is. *Basic* categories use the default handling rules; *Specified* categories come with extra rules from the law that created them, which is why the model gives a Specified category *implied controls*.
- A **dissemination control** narrows who may receive the information, below the default that anyone with a lawful government purpose may. The Registry allows a fixed set; the plan models four.
- A **marking** is the banner on a document: its categories and its controls, and for list-based controls, the list itself. **Portion marking** puts a marking on each paragraph; the plan leaves it open.
- **Decontrol** is the end of protection, on a date or an event. After it, the dissemination rules stop applying — but the document still belongs to a program, so ordinary access rules do not.
- The **designating agency** is the one that decided the information was CUI. Its offices hold the authority to change markings.
- **Lawful government purpose** is the legal basis for access: an activity the government authorizes. The example models it as *assignment to a program*.
- **Training** is required of every person who handles CUI. It is a procedure the organization evidences, not a fact the library checks, which is the plan's way of keeping the library out of HR.

**The four controls, and the idea of shape.** The Registry has around ten dissemination controls. The plan models four because each is a different *shape of test on the subject*: FED ONLY tests an attribute for a value (employment is federal); NOFORN compares a subject attribute with an object attribute (nationality against the designating agency's); REL TO tests membership of a subject attribute in an object's list (nationality in the countries list); DL ONLY tests the subject's identity against a per-document list, which is a direct, per-object grant. The other controls are one of these four shapes with different values — adding them is another row in a table, not another mechanism. That is what "one per shape" means.

**The model, read line by line.**

```
Agency ──< Office(designating) ──< Program ──< Assignment(user, role: lead | member)
```
An agency is the tenant — the customer. It has offices, which designate; offices run programs; people are assigned to programs with a role. Assignment is the lawful government purpose.

```
Office  ──< OfficeRole(user, role: designator | approver)
```
Separately from program membership, an office grants two authorities: designators change markings, approvers approve those changes. Two roles, so that C9 can require they be held by different people.

```
Program ──< Document(designated_by: Office, marking: Marking, decontrol: date | event | nil)
Document ──< Portion(marking: Marking)
```
A document belongs to a program, remembers which office designated it, carries a marking and possibly a decontrol. Portions are the open question.

```
Marking  = (categories: [Category], controls: [Control], list: [User])
Category(name, specified?: bool, implied_controls: [Control])
Control  : federal_only | no_foreign | named_list | releasable_to([country])
User(employment: federal | contractor, nationality)
```
A marking is categories plus controls plus, for DL ONLY, a list. A Specified category implies controls. A user has the two attributes the controls test.

**The rules, and what each is for.** C1 is the tenant rule: lawful purpose, via assignment or office role. C2 says every control must pass — all of, not any of. C3 says implied controls are computed, never copied, so a category's rule cannot drift from its documents. C4 is the banner rule, open with portions. C5 is decontrol, and it needs the clock. C6 says the named list is a grant on top of C1, never a replacement for it — being on a list does not give you a lawful purpose. C7 is who may change markings; C8 adds re-authentication to that; C9 adds separation of duties. C10 is the audited override. C11 is continuous evaluation, C12 the revocation clock, C13 scope fidelity — the three rules about the mechanism rather than the domain, kept in the same table because an assessor tests them alongside the others.

**Where the adapters differ on it.** OpenFGA walks implied controls and portions through the graph with nothing copied, and expresses "a different approver" as `but not proposer` — the cleanest of the four for C3, C4, and C9 — but its `scope` is a capped list of ids and it gates no writes. Postgres can refuse a C7-violating write without application code. Cerbos lets a policy owner in the agency's compliance office own C2–C6 as versioned files. Cerbos cannot compute C3 and C4 by itself — it only sees attributes it is sent — so the example materializes effective controls per document, or `scope` degrades to per-row filtering and the statement records "limited." Explanation differs: Cerbos names the rule that matched, code names the clause, Postgres says only yes or no.

---

## 11. FedRAMP, from the beginning

**The lineage.** A 2002 law, FISMA, made federal agencies responsible for securing their information systems according to NIST's standards. FIPS 199 tells an agency to rate each system's impact — Low, Moderate, or High — by what a breach would do to confidentiality, integrity, and availability. **NIST SP 800-53** is the catalog of controls that can be applied; its companion 800-53B picks a **baseline** for each impact level, a subset of the catalog that a system at that level must address. **FedRAMP** — the Federal Risk and Authorization Management Program, created in 2011 and written into law in 2022 — is the government-wide program for doing this once for a cloud service, so that every agency can rely on the same assessment instead of repeating it. "FedRAMP Moderate" means the Moderate baseline of 800-53 with FedRAMP's additions and parameter values.

**What a control looks like.** A control has a family and a number: AC-2 is Account Management, in the Access Control family. Its text is a numbered list of things the organization does. It may have **enhancements** — AC-2(4), Automated Audit Actions — which are optional sharpenings that a baseline may or may not include. Many controls have blanks: "review accounts [Assignment: organization-defined frequency]." Those blanks are **organization-defined parameters**, ODPs, and FedRAMP fills some of them itself — a **FedRAMP-assigned parameter** — so that every provider answers the same question. The families the plan cites: AC access control, AU audit and accountability, IA identification and authentication, PS personnel security, CM configuration management, AT awareness and training.

**Beyond baseline.** The catalog has over a thousand controls and enhancements; Moderate selects a few hundred. A control outside the baseline can still be cited — AC-25, the reference monitor, is the plan's favorite — but it is not required, and the statement marks it so nobody mistakes an extra for an obligation.

**The authorization package.** The set of documents a provider produces:

- The **System Security Plan**, SSP, is the central document. For each control it holds a **control implementation statement** — prose saying how this system meets it — an **implementation status** (Implemented, Partially Implemented, Planned, Alternative Implementation, Not Applicable), and a **control origination**.
- **Origination** says who is accountable. The seven values, in plain words: *Service Provider Corporate* — the company does this everywhere, not just in this system (an HR policy); *Service Provider System Specific* — this system does it; *Service Provider Hybrid* — some of each; *Configured by Customer* — the customer sets it in the product's settings; *Provided by Customer* — the customer brings it (their own identity provider); *Shared* — both sides carry part; *Inherited from pre-existing authorization* — the platform underneath, already authorized, provides it.
- The **Customer Responsibility Matrix**, CRM, lists what customers must do for each control where they carry part.
- The **Plan of Action and Milestones**, POA&M, is the tracked list of gaps: each with a description, how it was found, what will fix it, and when.
- The **inventory** lists every component inside the **authorization boundary** — the drawn line around what is being authorized. Every server, sidecar, and database inside the line is on the list and has its own scanning and hardening obligations, which is why the plan counts a policy engine as a cost.
- A **3PAO**, a third-party assessment organization accredited by FedRAMP, tests the system against the SSP and writes the **Security Assessment Report**, SAR. An agency's authorizing official reads the package and grants an **authorization to operate**. Then **continuous monitoring**, ConMon, begins: monthly scans and POA&M updates, annual reassessment.

**The word "compliant."** Nobody in this world says a system *is* compliant. A system is *authorized*, by a named official, on the strength of evidence a 3PAO checked. The plan's word is *assessment-ready*: the evidence exists and is honest. It avoids "FedRAMP Ready" too, because that phrase was a formal designation with its own meaning.

**20x.** In 2025 FedRAMP began a second path. Instead of a narrative per control, a provider addresses **Key Security Indicators**, KSIs — around sixty outcome statements for Moderate, each mapped back to 800-53 controls — and must provide *machine-readable* evidence produced by automated validation, which the 3PAO reviews as code. Reports go out quarterly as an **Ongoing Authorization Report**. The Moderate pilot ran over the winter of 2025–26 and the first authorizations were granted in spring 2026. FedRAMP is also renaming the impact levels, which is why the plan keeps "Moderate" out of module names and treats it as an input.

**Two tracks, one catalog.** Both tracks cite 800-53. So the plan keys every scenario by control id, tags each with the KSI it validates, and has the generator print either shape from the same declarations. Under 20x the plan's thesis is almost literally the program's thesis: the conformance suite *is* the validation code, and "regenerated on every build" is the reporting cadence.

**OSCAL.** The Open Security Controls Assessment Language is NIST's machine-readable format — JSON, YAML, or XML — for catalogs, baselines (called *profiles*), SSPs, assessment results, and POA&Ms. FedRAMP publishes its baselines and templates in it and accepts SSPs in it. The plan reads OSCAL in (the catalog, the Moderate profile) and writes OSCAL out (the SSP).

**Two axes that look like one.** The library knows a **responsibility split**: for each control, whether the library implements it, the application must, or the organization must. That is a statement about *who builds it*, and it becomes the rows of the CRM. Origination is a statement about *who is accountable on the SSP*, and only the provider can make it — the same library-implemented check is "Service Provider System Specific" for a SaaS company and might be "Shared" for a platform whose customers run the policy. So the generator carries both: origination is a field in the application's declaration, with defaults per adapter and the example's defaults for its own domain (programs and lists an agency sets → Configured by Customer; training → Service Provider Corporate).

**How fast the words change, and pinning.** Three vocabularies, three speeds. The port's words are from a 2014 guide that has never been revised, resting on 1972; they do not move. Control ids are stable for life — a control keeps its number, withdrawn ones are never reused, and revisions add rather than rename; major revisions come every four to seven years and small patch releases about every two. FedRAMP's program vocabulary — the SSP's field values, the KSI ids, the impact-level names — is changing on a cadence of months right now. The plan keeps each vocabulary where its speed is harmless: core and adapters speak only the first; scenarios cite the second; only the generator speaks the third, and it reads the third from **pinned sources** — a specific release of the catalog, of the Moderate profile, and of the 20x docs, named in one file. When any of them changes, bumping the pin produces a diff of affected scenarios, and that diff is the whole of the work.

---

## 12. The generator: from tests to statements

**The idea.** Everything above produces artifacts a machine can read: adapter declarations, an application declaration, test results, configuration, pinned sources. The generator, `mix turnstile.assess`, folds them into the documents an assessor reads. The plan's bet is that if the library owns the history and the decisions, most of the evidence writes itself.

**Declarations.** Each adapter declares, per scenario, whether it supports the behavior natively, in a limited way, or not at all; a default origination profile; the parameters it exposes; its inventory item; its measured revocation latency. The application declares its fact mapping, its origination overrides, its ledger mode, its settings.

**Scenarios.** A scenario is a test whose name is a sentence — "a revoked assignment is denied within the configured delay" — that cites a control id and a KSI id. The bar for a scenario to exist: a control in the Moderate baseline, or a KSI, names the behavior; second, an adapter differs on it. Scenarios all adapters pass identically are kept, because a buyer checks them off. A **lint** checks every cited control against the pinned catalog, its membership against the pinned baseline profile, and every KSI against the pinned docs — so a citation cannot be invented and a revision cannot silently invalidate one.

**Two tiers.** Tier 1 lives in core and tests the port's guarantees over a tiny neutral fixture — two object types, two roles, one attribute, one relationship, as Ecto schemas against the same Postgres the rest of the suite uses. A third party's adapter passes Tier 1 and receives a statement without ever seeing the CUI example. Tier 2 is the CUI scenarios, run once per adapter.

**What comes out, per control.** The implementation statement with its status and the component that implements it; the origination; the responsibility split; the parameters in force, split into FedRAMP-assigned and provider-chosen; the evidence — scenario ids and results, commit, date, adapter and engine versions, measured latency, ledger mode, pinned source versions; the inventory items; and a POA&M row for every unsupported cell and every known drift window, in the POA&M template's columns, stating plainly what would close it.

**Two profiles.** Rev 5 prints markdown and an OSCAL SSP with POA&M and CRM. 20x prints, per KSI, the validating scenarios and their results as JSON in the pinned docs' shape.

**Two more tasks.** `--diff <ref>` prints what changed between two statements, which is both the adoption path's progress bar and a 20x quarterly report's delta. `mix turnstile.review` prints the account and privilege review for today and, once the ledger has history, for a date.

**Why every build.** Because the eighth question — can you keep producing this — is answered only by a process, and a process that runs in CI is one an assessor can watch.

---

## 13. The adoption path, walked from your application

Your application today: Phoenix and Ecto; a JWT whose claim carries a role; a plug that checks the role and lets the request through; queries scoped by tenant. Here is the path, in prose, with the chapter each step leans on.

**Step 0 — see the whole gap.** Add `turnstile_core`. Run the generator: every control prints Not Implemented, and that is the honest baseline. Turn the mediated Repo on in audit mode (chapter 5). Nothing changes for users; the log fills with every Repo call that carried no decision. That list is your inventory — the CSV export, the report, the job.

**Step 1 — get the role out of the token.** The token keeps identity only. A plug looks up roles and attributes per request and builds the subject (chapters 3 and 8). Revocation latency drops from the token's lifetime to one request. Nothing else changes yet.

**Step 2 — route the one check you have through the port.** The code adapter, one role, one permission called `access`. Behavior is identical; the difference is that every request now emits a decision event and deny-by-default holds for any request that does not reach the check (chapter 7). Two audit controls turn green with no visible change to the product.

**Step 3 — enforce mediation.** Flip the Repo from audit to enforce and work the step-0 list: each entry either gets a decision or a named exemption. When the list is empty, "always invoked" is true (chapter 5).

**Step 4 — split the role.** Declare the role→permission table: at least a non-privileged role and a privileged one, security functions under the privileged one, privileged people on separate accounts (chapter 9). Every controller action names its operation, which is where the generated per-operation functions arrive. Least privilege and separation of duties become scenarios you pass.

**Step 5 — scope through the seam.** Your tenant scoping moves into the `dynamic` the adapter returns, applied in `prepare_query` (chapter 4). Tenant isolation is now proven by a fidelity test rather than assumed from convention.

**Step 6 — the privileged paths.** Support and operator access go through the audited override: justified, logged, reported (chapter 9).

**Step 7 — re-authentication.** Sensitive operations read the session's last-authenticated fact and refuse stale sessions (chapter 8).

**Step 8 — review.** `mix turnstile.review` prints who can do what, today. This is the account review an assessor asks for by name.

**Step 9 — history.** Add `turnstile_ledger`, declare the membership table a fact schema, run genesis (chapter 6). From this date forward, replay and point-in-time review exist, and the statement says when they began.

**Step 10 — a second layer, if you want one.** Postgres row-level security beneath the code adapter for defense in depth and write gates (chapter 4), Cerbos when the people who own the rules stop being the people who ship code, or OpenFGA when the domain is a graph or the organization already runs one (chapter 3).

**If your application has no Ecto.** Steps 1, 2, 4, 6, 7, and 8 apply as written; 3, 5, 9, and 10 do not, and the statement prints mediation, scope, and history as your own claims. The event-store ledger mode is how you give it history.

**The example walks the same path.** The example application begins as a tag, `v0-jwt-single-role`, with no Turnstile in it, and each step above is the next tag with its generated statement committed beside it. The adoption guide is that tag list, annotated. CI checks out each tag and regenerates the statement to make sure the guide and the code have not drifted apart — a guide that cannot rot, or at least cannot rot silently.

---

## 14. Roads not taken, and why

**Leaving the relationship graph out.** An earlier draft dropped OpenFGA on boundary cost — a server and a second database holding copies of the facts, each a component with its own scanning, hardening, and paperwork. A design exercise (`OPENFGA.md`) showed the port, the seam, and the events survive it untouched, that three of the CUI rules come out cleaner on a graph than anywhere else, and that its costs are exactly the kind of thing the statement exists to print. So it is in — as the fourth adapter, with its costs on the page — and the example is built once per adapter so a team chooses from four statements side by side rather than from a README's opinion.

**A hosted decision service.** An external service the request path depends on is, in FedRAMP's eyes, another system needing its own authorization or an interconnection agreement. Self-hosted only.

**Facts in tokens.** Frozen until expiry; revocation waits for the clock. Identity only.

**Compile-time mediation.** A heuristic that could not see writes two calls down, in jobs, or in raw SQL. Replaced by the Repo seam, which sees everything that goes through the Repo, at runtime, and lists what does not.

**A filter language of core's own.** An earlier draft had `scope` return a small language that a separate package compiled to Ecto, so that core would not depend on Ecto. The language guaranteed that scope only narrows and put a faithful record of the filter in the decision event, but a `dynamic` gives both without a language to design or a second compiler to trust, and it can express subqueries, which the language could not. Core depends on Ecto's query library; a port is independent on the axis that is swapped, and that axis is engines.

**Projection lag.** A leftover from the graph adapter, which really did have a delay between a fact and its copy. With the three chosen adapters the working state is the tables, so the meaningful number is the end-to-end revocation latency, measured rather than reasoned about.

**Event-sourcing the application.** A large architectural choice that belongs to the application. The plan event-sources authorization facts only, and lets an already event-sourced application bring its own store.

**"Compliant."** Not a thing anyone grants. Assessment-ready, authorized by an official, on evidence.

**Database portability.** Declined beyond what Ecto already gives: MySQL and SQL Server dialects are written on request, not in advance, and the statement says which database was tested rather than claiming the rest. The line sits at the port, and the top layer stays database-free so that the unusual shop still has a use for the library.

**"Provider."** The natural word for an adapter, and FedRAMP's word for the cloud service provider — the customer of this library. One word per meaning; adapter it is.

---

## Appendix A — terms in one place

| Term | Plain meaning | Chapter |
|---|---|---|
| Reference monitor | The part of a system that checks every access; must be always invoked, tamperproof, and small | 1 |
| Subject / object / operation / environment | Who is asking, about what, to do what, under what conditions | 2 |
| Attribute | A fact about a subject or object that a rule can test (role, tenant, nationality) | 2 |
| RBAC / ABAC / ReBAC | Rules over roles / over any attribute / over relationships in a graph | 2 |
| Role explosion | Roles multiplying to encode what should be an attribute | 2 |
| PEP / PDP / PIP / PAP | Where a request is stopped / where the answer is computed / where attributes come from / where rules are written | 3 |
| Port / adapter | The interface in core / an implementation of it for one mechanism | 3 |
| Conformance suite | The tests any adapter must pass; the real contract | 3 |
| Deny by default / fail closed | No unless a rule says yes / no when the system cannot decide | 3 |
| Sidecar | A small server running beside the application (Cerbos) | 3 |
| Authorization boundary | The drawn line around what is being authorized | 3, 11 |
| `scope` / `dynamic` | Narrow a query to what the subject may see / the Ecto where-clause fragment it returns, which can only narrow | 4 |
| Scope fidelity | `scope` returns exactly the rows `check` would allow | 4 |
| Row-level security | Postgres policies applied to every query on a table; `USING` for reads, `WITH CHECK` for writes | 4 |
| Write gate | A rule the database enforces on inserts and updates without application code | 4 |
| Mediated Repo | A Repo that refuses calls carrying no decision and no exemption | 5 |
| Exemption | A named, logged opt-out from mediation | 5 |
| Audit mode / enforce mode | Log unmediated calls / refuse them | 5 |
| Event / ledger / fold / replay | An immutable record of a change / an append-only list of them / reducing them to state / folding up to a date | 6 |
| Fact event (four kinds) | Subject attribute set or cleared; object attribute set or cleared; relationship granted or revoked; policy version published | 6 |
| Fact mapping | The translation from an application's schemas to the four kinds | 6 |
| Ledger position | The index in the ledger a decision was made at | 6 |
| Genesis | The backfill that gives an existing application's ledger an origin | 6 |
| Drift / reconcile | Facts changed outside the seam / periodically checking the tables against the ledger | 6 |
| Audit record | A log entry with the shape AU-3 requires | 7 |
| Telemetry | Elixir's convention for a library to publish events that handlers consume | 7 |
| SIEM | The security team's central log system; a sink | 7 |
| Hash chain / anchoring | Each record hashes the previous; keeping the head somewhere the attacker cannot write | 7 |
| Continuous evaluation | Attributes looked up on every check, never cached across requests | 8 |
| Revocation latency | Time from a revoking change to the first denial | 8 |
| Environment fact (port-supplied / caller-supplied) | Time from the clock behaviour / facts only the caller knows | 8 |
| Re-authentication | Prove it is still you before sensitive operations | 8 |
| User / NPE / privileged user | A person / software acting alone / a person who can change the system | 9 |
| Least privilege / separation of duties | The least access needed / dangerous combinations split between people | 9 |
| Audited override (break-glass) | Privileged access past the rules, with justification, logging, and reporting | 9 |
| CUI | Controlled unclassified information; protected by law, below classified | 10 |
| Category (Basic / Specified) | What kind of information; Specified brings its own handling rules | 10 |
| Dissemination control | Who may not receive it, below the default | 10 |
| Marking / portion marking / decontrol | The banner / per-paragraph banners / the end of protection | 10 |
| Designating agency / lawful government purpose | Who declared it CUI / the legal basis for access | 10 |
| FISMA / FIPS 199 / 800-53 / 800-53B | The law / impact levels / the catalog / the baselines | 11 |
| Control / enhancement / family | A requirement (AC-2) / an optional sharpening (AC-2(4)) / a group (AC) | 11 |
| ODP / FedRAMP-assigned parameter | A blank in a control / a blank FedRAMP fills | 11 |
| Baseline / beyond baseline | The subset required at an impact level / cited but not required | 11 |
| SSP / implementation statement / implementation status | The central document / how a control is met / Implemented, Partially, Planned, Alternative, N/A | 11 |
| Origination (seven values) | Who is accountable for a control on the SSP | 11 |
| Responsibility split | Library / application / organization — who builds it; feeds the CRM | 11 |
| CRM / POA&M / inventory | Customer duties per control / tracked gaps / components in the boundary | 11 |
| 3PAO / SAR / ATO / ConMon | The assessor / their report / the authorization / monthly monitoring | 11 |
| 20x / KSI / Ongoing Authorization Report | The automation-first track / its outcome statements / its quarterly report | 11 |
| OSCAL | NIST's machine-readable format for catalogs, profiles, SSPs, results, POA&Ms | 11 |
| Pinned sources | Specific releases of the catalog, the profile, and the 20x docs, named in one file | 11 |
| Dialect | The ledger's per-database module — batch size, returned rows, reader strategy, lock clause, append-only grant; Postgres and Generic ship | 3 |
| The line | Opinionated below the port (Ecto, Postgres), database-free above it, checked at compile time | 3 |
| Assessment-ready | The plan's word; never "compliant," never "FedRAMP Ready" | 11 |
| Declaration / scenario / lint | What an adapter or application states about itself / a cited test / the check on citations | 12 |
| Tier 1 / Tier 2 | Port guarantees over a neutral fixture / CUI scenarios per adapter | 12 |
| `--diff` / `review` | What changed between statements / who can do what, today or on a date | 12 |

## Appendix B — from the plan to this document

| Plan section (v7) | Chapters |
|---|---|
| Who it is for | 1, 11 |
| Words | 2, 11 |
| The question | 2, 3, 8, 9 |
| Decisions | 7 |
| Facts | 6 |
| The ledger | 6, 7 |
| The seam | 1, 4, 5 |
| Audit | 7 |
| Adapters | 3, 4 |
| The line | 3 |
| The example | 9, 10 |
| Evidence | 11, 12 |
| Adoption | 13 |
| Decisions, each with the alternative it rejected | 14 |
| `REFERENCE.md` | the tables and numbers behind chapters 5, 7, 10, and 11 |
