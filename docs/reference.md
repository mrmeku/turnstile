# Turnstile: reference notes

*Tables, numbers, and mechanics at implementation grain. Nothing here is a decision `PLAN.md` does not already make; this is where those decisions are spelled out against the code. The section numbers are this document's own, and the documents and modules that cite them cite these. ⟨verify⟩ marks a claim to check against the standard cited or against the pinned Ecto before relying on it.*

## §1 Requirement groups, controls, and scenario ids

Enhancement membership in the FedRAMP Rev 5 Moderate profile is ⟨verify⟩. Beyond-baseline citations are allowed and marked. A scenario id is the group's prefix, a hyphen, and a two-digit number (§3a).

| Group | Id prefix | Moderate baseline controls | Beyond baseline (cited, marked) |
|---|---|---|---|
| Enforcement | `enf` | AC-3 | AC-25 always invoked; AC-3(7) role-based |
| Least privilege | `lp` | AC-6, AC-6(1), (2), (5), (9), (10); AC-2(7) | |
| Separation of duties | `sod` | AC-5 | |
| Revocation and expiry | `rev` | AC-2, AC-2(1), (2), (3); PS-4, PS-5 | AC-3(8) revocation of authorizations; AC-16 security attributes |
| Decision audit | `aud` | AU-2, AU-3, AU-3(1), AU-12, AC-2(4); AU-9, AU-9(4), AU-11 | |
| Access review | `rvw` | AC-2 account review; AC-6(7) | |
| Re-authentication | `ia` | IA-11 | |
| Emergency override | `ovr` | AC-6(9), AC-2(2), AU-6 | |
| Change control on policy | `cm` | CM-3, CM-5 | |

Notes.
- AU-2: the FedRAMP-assigned parameter names, for web applications, authorization checks, data access, data changes, and permission changes among the events to log ⟨verify Rev 5 wording⟩. "Every call is evented" is that parameter, met.
- Change control is a strength to show: for RBAC and Postgres a policy version is a commit and a deploy, so review is approval; the scenario asserts every policy-version event names its author and its approval.
- Tenant isolation: SSPs answer the multi-tenant separation question under AC-3 and SC-4/SC-7; the C13 scenario across agencies is where it is proven.
- Training (AT-3) and CUI marking rules (32 CFR 2002) are organization-level; no scenario tests them.

## §2 Dissemination controls and the portion

A category says what the information is; a control says who may not receive it, below the default that anyone with a lawful government purpose may. The Registry allows a fixed set; a document may carry several; all must hold. Four modeled, one per shape of subject test; FEDCON, NOCON, DISPLAY ONLY, and the attorney markings are the same shapes with other values.

| Control | Registry marking | Test on the subject |
|---|---|---|
| `federal_only` | FED ONLY | employment is federal |
| `no_foreign` | NOFORN | nationality matches the designating agency's |
| `named_list` | DL ONLY | the subject is on the marking's list, a per-object grant |
| `releasable_to` | REL TO | nationality is in the marking's country list |

**The portion**. `Portion(document_id, marking: Marking)` is a row under `Document`; a document may have none. The document's marking is its banner, the marking under which every one of its portions may be read (§3 rule C4, enforced at write time in the domain). `Portion` declares its own object type, is not a carried relation of `Document`, and its `marking` is a fact field of kind `:object_attribute`.

Two read operations on a document. `read` is the whole document under the banner: a Document decision under C1 and C2 over the banner. `read_redacted` returns the document with the portions the subject may not read removed: a Document decision under C1 (`authorize(subject, :read_redacted, document)`), then a Portion `scope` (`scope(subject, :read, Portion)`) whose `dynamic` the seam applies to the portions query, `Repo.preload(document, :portions, turnstile: portion_decision)`. Because `Portion` is not carried, a preload without its own decision is refused (§6). Scope fidelity (C13) holds at portion level: the portions returned are exactly those for which `check(subject, :read, portion)` is true. Each adapter filters portions as rows of their own under a policy of their own:

| Adapter | Portion mechanism |
|---|---|
| `turnstile_rbac` | a `read` operation on `Portion` whose predicates are the document predicates over the portion's marking |
| `turnstile_postgres` | a second row-level security policy on the `portions` table; the `documents` policy is not consulted for portion rows |
| `turnstile_cerbos` | a `portion` resource kind with its own policy; `scope` over portions with derived markings falls back to `filter` (§3) |
| `turnstile_fga` | a `portion` type with a `document` parent, the control flags on the portion, and `can_read: lawful_purpose from document but not blocked` (§13) |

## §3 Rules and mechanisms

The thirteen rules of the example's domain, as a person wrote them. `apps/example/glossary.md` defines the words they use.

| Rule | Statement |
|---|---|
| **C1 Lawful purpose** | `read` on a Document requires an Assignment to its Program or an OfficeRole in its designating Office. |
| **C2 Controls, all of** | Every Control on the effective marking is a test on the subject, and all must pass. |
| **C3 Specified categories** | A Specified category adds its implied Controls. Effective controls are declared ∪ implied. Nothing is copied. |
| **C4 Banner** | A Document's banner admits no subject a Portion of it denies. Categories and Controls are the union of the Portions'; the REL TO country list is the intersection of the lists of the Portions that carry that control, so a country one Portion withholds is released by no banner. The banner is kept at write time in the domain and tested as a scenario. A change to a Portion's marking recomputes the banner in the same transaction; a banner that would admit a subject a Portion denies is refused. |
| **C5 Decontrol** | After the decontrol date or event, C2 to C4 no longer apply; C1 still does. The current time is a port-supplied environment fact. |
| **C6 Named list is a direct grant** | `named_list` membership is per Document per User and combines with nothing; it never overrides C1. |
| **C7 Marking gates** | Changing a marking, setting a decontrol, or decontrolling requires a `designator` role in the designating Office. |
| **C8 Re-authentication** | C7 operations additionally require the session to have re-authenticated within a configured window. |
| **C9 Separation of duties** | A marking change proposed by one designator must be approved by a different approver. |
| **C10 Audited override** | A privileged user holding the override permission may read a Document outside C1 with a justification; the read succeeds, always emits its own event, and is reported to the designating Office. Never unconditional. |
| **C11 Continuous evaluation** | Assignments, list membership, employment, and nationality are evaluated at every check; a change deletes nothing. |
| **C12 Revocation clock** | A revoked fact is enforced within the configured maximum delay. The measured latency is recorded beside the configured maximum; no test asserts it. |
| **C13 Scope fidelity** | `scope` returns exactly the rows for which `check` is true, for Documents and for Portions. |

**What enforces each rule.** Each thin application's README carries a table of the rules against what enforces each of them under that binding: the engine, the seam, the adapter, or the application's own code. That table is prose a person writes and keeps, and no code reads it. What a test carries instead is its tags. The `scenario` macro tags each test with its scenario id, the rule it tests, and the controls §3a cites for that id, so a control id is written once, in §3a, and the tags are what a run reports from.

**Where the adapters differ.** Write gates without application code: Postgres only, where a C7-violating marking change is refused by the database whether or not the application asked. That is a property of Postgres rather than a rule, and no scenario tests it. Rules owned by non-developers, versioned and tested as their own artifact: Cerbos only. Explanation: Cerbos names the matched rule, code names the clause, OpenFGA returns the path from `Expand`, and Postgres answers a verdict with an empty match list. Derived markings, which are C3 and C4 through portions: Cerbos plans over the attributes it is sent alone, so the derivation lives in the subquery a declaration names rather than in the policy, and nothing is materialized; OpenFGA walks them as tuple-to-userset, also with nothing copied. Request-time facts, which are C5 and C8: every adapter answers them, Postgres threads them through session settings, and OpenFGA takes C5 as a tuple condition with the moment in the check context and C8 in the adapter, from the environment, before the call. OpenFGA alone: C9 is `approver from office but not proposer`, and `scope` is `ListObjects` under a cap. The model and the tuple mapping are §12.

## §3a Tier 2 scenarios

Frozen with the contracts, and the freeze test in `turnstile` reads this table and holds `Turnstile.Conformance.Scenarios` to it row for row. Every row is a test in `Example.Scenarios` whose name is the sentence, written with the `scenario` macro (`scenario "enf-01", "<sentence>", rule: :c1 do ... end`, §13), and run by each of the four thin applications. "Tests" names the C-rule, or the guarantee where the scenario tests the port or the seam in the domain's words. Beyond-baseline citations are marked with an asterisk.

| Id | Sentence | Group | Controls cited | Tests |
|---|---|---|---|---|
| `enf-01` | A User with an Assignment to a Document's Program reads it | enforcement | AC-3 | C1 |
| `enf-02` | A User with neither an Assignment nor an OfficeRole is denied the Document | enforcement | AC-3 | C1 |
| `enf-03` | A User holding an OfficeRole in the designating Office reads a Document of that Office's Program without an Assignment | enforcement | AC-3 | C1 |
| `enf-04` | A contractor is denied a FED ONLY Document they are assigned to | enforcement | AC-3, AC-16* | C2 |
| `enf-05` | A foreign national is denied a NOFORN Document of a domestic Agency | enforcement | AC-3 | C2 |
| `enf-06` | A User whose nationality is outside the REL TO list is denied the Document | enforcement | AC-3 | C2 |
| `enf-07` | A User on the DL ONLY list reads the Document and one not on it is denied | enforcement | AC-3 | C2, C6 |
| `enf-08` | A Document carrying two controls is denied to a User who clears one of them | enforcement | AC-3 | C2 |
| `enf-09` | A Specified category's implied control blocks a User the declared controls would allow | enforcement | AC-3 | C3 |
| `enf-10` | A Document with no controls is read by any User with a lawful purpose | enforcement | AC-3 | C2 |
| `enf-11` | A NOFORN Portion is removed from a foreign national's redacted read while the rest of the Document returns | enforcement | AC-3 | C4, C13 |
| `enf-12` | A Document marking that would drop a Portion's control is refused at write time | enforcement | AC-3, AC-16* | C4 |
| `enf-13` | After the decontrol date a contractor reads a FED ONLY Document they are assigned to | enforcement | AC-3 | C5 |
| `enf-14` | Before the decontrol date, by the port's clock, the same Document is denied | enforcement | AC-3 | C5 |
| `enf-15` | A decontrolled Document is still denied to a User with no lawful purpose | enforcement | AC-3 | C5, C1 |
| `enf-16` | DL ONLY membership without an Assignment does not grant the read | enforcement | AC-3 | C6 |
| `enf-17` | The Documents `scope` returns are exactly the Documents `check` allows, over random subjects | enforcement | AC-3, AC-25* | C13 |
| `enf-18` | The Portions `scope` returns are exactly the Portions `check` allows | enforcement | AC-3 | C13 |
| `enf-19` | A Document of another Agency is neither returned by `scope` nor readable by `check` | enforcement | AC-3 | C1, C13 |
| `enf-20` | A User one Portion releases to and another does not is denied the whole Document | enforcement | AC-3, AC-16* | C4, C2 |
| `lp-01` | A Program member without an OfficeRole cannot change a Document's marking | least privilege | AC-6, AC-6(1) | C7 |
| `lp-02` | A designator of another Office cannot change the marking | least privilege | AC-6(1) | C7 |
| `lp-03` | A designator of the designating Office changes the marking | least privilege | AC-6(1) | C7 |
| `lp-04` | Setting a decontrol needs a designator | least privilege | AC-6(1) | C7 |
| `lp-05` | A Portion's marking change needs a designator of the Document's designating Office | least privilege | AC-6(1) | C7, C4 |
| `lp-06` | An ordinary account cannot invoke the override | least privilege | AC-6(10) | C10 |
| `lp-07` | A privileged account is a separate account: the same person's ordinary account cannot override | least privilege | AC-6(2) | C10 |
| `lp-08` | The access review lists every privileged account and every permission a role holds | least privilege | AC-6(5), AC-2(7) | C7, C10 |
| `sod-01` | A marking change proposed by a designator is approved by a different approver | separation of duties | AC-5 | C9 |
| `sod-02` | The proposer, who is also an approver, cannot approve their own proposal | separation of duties | AC-5 | C9 |
| `sod-03` | A proposal without approval does not change the marking | separation of duties | AC-5, CM-5 | C9 |
| `rev-01` | A revoked Assignment denies the next check; the measured latency and its components are recorded, never asserted | revocation and expiry | AC-2, PS-4, AC-3(8)* | C11, C12 |
| `rev-02` | Removal from a DL ONLY list denies the next read | revocation and expiry | AC-2, AC-2(1) | C11 |
| `rev-03` | A change of employment from federal to contractor denies a FED ONLY read at the next check | revocation and expiry | AC-2, PS-5 | C11 |
| `rev-04` | A corrected nationality applies at the next check | revocation and expiry | AC-2, AC-16* | C11 |
| `rev-05` | A closed Program revokes every Assignment's lawful purpose at the next check | revocation and expiry | AC-2, AC-2(3) | C11 |
| `rev-06` | A tightened rule, published as a policy version, is enforced within the measured propagation, which is recorded | revocation and expiry | AC-2, CM-3 | C12 |
| `rev-07` | A revocation deletes nothing but the fact: the Document and the Program remain, and the grant and the revoke are both evented | revocation and expiry | AC-2(4) | C11 |
| `aud-01` | Every Document read emits one decision event carrying subject, object, operation, verdict, reason, and policy version | decision audit | AU-2, AU-3, AU-12 | every call is evented |
| `aud-02` | A denied read emits its event with the reason | decision audit | AU-2, AU-3 | every call is evented |
| `aud-03` | A decision record carries no attribute value | decision audit | AU-3 | record shape |
| `aud-04` | A marking change emits one decision event and, in the same transaction, a change event per row it wrote, the banner's carrying every changed fact field | decision audit | AU-12, AC-2(4) | no change without an event |
| `aud-05` | A bulk re-marking of Documents is refused and no Document changes | decision audit | AU-12, AC-2(4) | a bulk write to an audited schema raises |
| `aud-06` | An Assignment grant and its revoke each produce a change event carrying old and new | decision audit | AC-2(4) | the change mapping |
| `aud-07` | A marking change reaches the consumer as one OCSF record per event, all under one correlation id | decision audit | AU-2, AU-3, AU-12 | every event is mapped |
| `aud-08` | A write the database refuses leaves no row and emits no change event | decision audit | AU-2, AU-12 | atomicity |
| `rvw-01` | The access review lists who can read what today, per Agency | access review | AC-2, AC-6(7) | `review` |
| `rvw-04` | An Assignment inserted outside the seam emits no change event, so the review reads it from the tables and no record names it | access review | AC-2, AC-2(4) | drift |
| `ia-01` | A designator whose session re-authenticated within the window changes a marking | re-authentication | IA-11 | C8 |
| `ia-02` | A designator whose session is older than the window is refused until re-authentication | re-authentication | IA-11 | C8 |
| `ia-03` | A marking change with no re-authentication fact supplied is denied | re-authentication | IA-11 | C8 |
| `ovr-01` | A privileged user with the override permission reads outside C1 with a justification, and the read emits its own event and is reported to the designating Office | emergency override | AC-6(9), AU-6 | C10 |
| `ovr-02` | Without a justification the override is denied | emergency override | AC-6(9) | C10 |
| `ovr-03` | The override never reaches C7: a privileged user cannot change a marking through it | emergency override | AC-6(9), AC-6(1) | C10, C7 |
| `cm-01` | Every policy-version event names its author and its approval | change control on policy | CM-3, CM-5 | policy versions |
| `cm-02` | A decision made under version N carries N after version N+1 is published | change control on policy | CM-3 | policy versions |
| `cm-03` | A rule change is a policy version whose event names the artifact it is on this adapter | change control on policy | CM-3 | policy versions |

No scenario tests "write gates without application code"; it is not a rule.

## §4 Adapters: comparison, declarations, notes

| Adapter | Package | Enforcement | Explains | Revocation latency components | Rules live in | Boundary cost |
|---|---|---|---|---|---|---|
| Roles in code | `turnstile_rbac` | the application's discipline, backed by the seam | the clause | commit | Elixir modules; a deploy is a policy version | none |
| Postgres row-level security | `turnstile_postgres` | the database; write gates need no application code | a verdict, with an empty match list | commit | migrations; a migration is a policy version | none new |
| Cerbos | `turnstile_cerbos` | the application's discipline; policies versioned and tested as their own artifact | the matched rule | commit for facts; the sidecar's policy poll interval for rules | policy files; a policy owner | one sidecar |
| OpenFGA | `turnstile_fga` | the application's discipline, backed by the seam; the graph decides | the path from `Expand` | commit, the relay pass, the engine write, and the check-cache TTL for facts; model publication for rules | a model file, published as an immutable model id; tuples the outbox keeps in step | a server and a datastore: two inventory items, one engine where the datastore shares the application's Postgres instance |

**What an adapter declares.** Two things, and both are true of the adapter in any domain, so both are callbacks of `Turnstile.Adapter` rather than a table someone keeps: `scope_cap/0`, the cap on the number of objects `scope` can return, `:none` where the rule is a query the database runs; and `settle/0`, whether the adapter has state of its own to settle before a test reads it. `options_schema/0` says what options the adapter takes, validated at boot. Nothing else is declared. What holds a rule under one binding is that thin application's README, and what a scenario tests is its tags.

- **Postgres.** The application role must not own the tables, or row-level security is bypassed, and it carries `NOBYPASSRLS`; `FORCE ROW LEVEL SECURITY` is on every protected table. Forcing it applies the policies to the owner as well, so the migrations give the owner role a `SELECT` policy on every protected table, which is what the reconcile and the accessor functions read through. Session settings are set inside `around_query/3`: the adapter opens a transaction where none is open, one per call, and runs `set_config(name, value, true)` for `turnstile.subject_id`, `turnstile.subject_kind`, `turnstile.operation`, `turnstile.now`, and one name per fact the caller supplied, such as `turnstile.reauthenticated_at`, so two subjects in one transaction each set their own; policies read them with `current_setting(name, true)`. Where the transaction was already open when the call arrived, the adapter puts the names it set back to the empty string as the call returns, so a query the seam admits outside a decision is not read under the settings of the last one. `check` for a write operation is a `SELECT` of the update policy's `USING` predicate, read from `pg_policy` at boot and cached per policy version, run against the target row under those settings; `authorize(subject, :change_marking, document, env)` answers before the write this way, and the write itself is then refused or admitted by `WITH CHECK`. A thin application that writes `USING (true)` on a gate moves the whole decision into `WITH CHECK`, so a write no one asked about raises instead of matching no row, and the `SELECT` policy of the operation is what narrows the answer. The policy expressions are read back from `pg_policy` for the policy-version event. Portions are a second policy on the `portions` table. The rules per binding are `example_postgres`'s README.
- **Cerbos.** Facts arrive with each request, so their latency is one request; rules arrive on the sidecar's policy poll interval, which is the latency for a policy change, measured from a publish. The sidecar's decision logs are reconciled with the port's decision events, and any difference is a drift scenario. Its `version` field on a policy runs variants side by side and is not history; history is the policy repository's commit. An attribute declaration maps a Cerbos attribute name to a column or to a subquery, and the query plan is compiled to a `dynamic` over declared attributes only; a plan over an attribute declared as a subquery becomes `in subquery(...)`, and a plan the compiler cannot express falls back to `filter`:

  ```elixir
  attribute :nationality, column: :nationality
  attribute :employment, column: :employment
  attribute :program_roles, subquery: &Example.Assignments.program_roles_for/1
  attribute :effective_controls, subquery: &Example.Markings.effective_controls_for/1
  ```

  Portions are a `portion` resource kind with a policy of its own.
- **Roles in code.** The role to permission table is declared data, and attribute predicates are functions in the same modules. Portions get a `read` operation of their own. Publishing a version emits telemetry and writes nothing, because there is no artifact to write: the rules are the modules the release carries.
- **OpenFGA.** The adapter talks to the server only through the `Turnstile.Fga.Client` behaviour, and an `Agent`-backed fake in test support answers it without a server. The store is a copy of what the tables say, kept in step by the outbox and the relay (§9) rather than by a fold of history. `Check` pins the model id and sets `consistency` per operation: `HIGHER_CONSISTENCY` under C7 to C10, `MINIMIZE_LATENCY` allowed for reads, which is a constant of the adapter; a check cache, where one is enabled, adds its TTL to latency. `ListObjects` has a result cap of 1,000, a constant of the adapter, and a deadline on the order of a thousand milliseconds ⟨verify⟩; above the cap the port falls back to `filter` per page with `BatchCheck`. Self-hosted means the open-source server; a hosted FGA is a hosted engine and inadmissible. Portions are a `portion` type with a `document` parent. The adapter is §12.

**Revocation latency as evidence.** Scenario `rev-01` writes a revoking fact through the seam, settles the adapter through `Turnstile.Test.settle/0`, and checks again. The measured milliseconds and the adapter's components are printed beside the run, and nothing asserts them: rule C12 asks for the number to be recorded, not bounded. An adapter that answers from the tables it is bound to has no state to settle, so `settle/0` answers `:none` and the line says the settle was not needed rather than reporting a zero that reads like a measurement. `rev-06` is the same shape over a rule change rather than a fact change, where the component is the sidecar's propagation for Cerbos and a model publication for OpenFGA.

## §5 Policy versions

A policy version is `%Turnstile.PolicyVersion{adapter, version, content_hash, content, pointer, author, approval, at}`. `content` is the text by value only where it is under `caps[:policy_content_bytes]`, 64 KB by default, and `pointer` names the store it lives in otherwise. Each adapter publishes one telemetry event when a version is deployed, and the library stores nothing: whoever keeps a record of what was deployed attaches a handler. A decision event carries the version identifier and never the content.

| Adapter | Event | Version | Published by | Carries |
|---|---|---|---|---|
| Roles in code | `[:turnstile, :code, :policy_version]` | the commit or release | the application at boot | the commit, a hash of the rule modules, and the role to permission table as data where it is under the cap |
| Postgres | `[:turnstile, :postgres, :policy_version]` | the migration number | the migration, in the same transaction as its DDL | the `USING` and `WITH CHECK` expressions read back from `pg_policy` |
| Cerbos | `[:turnstile, :cerbos, :policy_version]` | the policy repository's commit | the policy repository's CI on merge | the commit, a hash of the files, and the files where they are under the cap |
| OpenFGA | `[:turnstile, :fga, :policy_version]` | the model id the server returns on publish | the model repository's CI on publish | the model id, the commit, a hash of the model file, and the DSL text where it is under the cap |

The metadata of each event is `%{version: %Turnstile.PolicyVersion{}}`. Scenarios `cm-01` to `cm-03` read the event a binding names through `Example.Scenarios.Rules.version_event/0`, which is what keeps an adapter's name out of the scenario bodies.

## §6 The Repo seam

`use Turnstile.Repo` after `use Ecto.Repo`; the macro raises at compile time where the order is wrong. The failure mode to defend against is silent: a function a core forgot to wrap runs unmediated.

**Classification** (`Turnstile.Core.Surface`), every `Ecto.Repo` function in exactly one bucket, written against Ecto 3.14 and `ecto_sql` 3.14:

- *query*, mediated through `prepare_query/3`: `all`, `all_by`, `one`, `get`, `get_by`, `reload`, `aggregate`, `exists?`, `stream`, `preload`, `update_all`, `delete_all`, and the raising variant of each.
- *write*, overridden: `insert`, `update`, `delete`, `insert_or_update`, `insert_all`, and the raising variant of each. Any of them called with `on_conflict:` is an upsert, and an upsert on an audited schema is refused.
- *raw*, wrapped to demand an exemption: `query`, `query_many`, and the raising variant of each.
- *plumbing*, touching no rows: `transaction`, `transact`, `rollback`, `in_transaction?`, `checkout`, `checked_out?`, `config`, `start_link`, `stop`, `child_spec`, `load`, `get_dynamic_repo`, `put_dynamic_repo`, `default_options`, `prepare_query`, `prepare_transaction`, `to_sql`, `explain`, `disconnect_all`, `__adapter__`, and the seam's own `__turnstile__`, which answers the repo's role.

**Matching** (`Turnstile.Core.Matching`). A schema is protected if and only if it declares an object type. Three rules decide which decision applies to which query:

1. The seam judges a query by its root source. A query whose root source is a protected schema and whose decision names a different object type is refused.
2. A preload or association query needs a decision of its own unless the parent schema declares the association as carried; a nested association write of another protected schema is refused unless that association is carried.
3. A multi-source query is judged by its root source, and every other protected source in it must be carried by the root.

Queries on unprotected schemas pass without a decision. The declarations sit in the schema module beside the fact mapping, from the same macro:

```elixir
defmodule Example.Document do
  use Ecto.Schema
  use Turnstile.Schema

  object_type(:document)
  carries([:program, :designating_office, :marking, :proposals])
  audited(:entity)
  # portions is not carried: the redacted read supplies a Portion decision (§2)
end
```

**Exemptions.** Two kinds, one struct: `%Turnstile.Exemption{on: schema | table | nil, caller: module | :any, reason: String.t(), kind: :declared | :library}`, where `on` is `nil` for raw SQL.

- Per call: `turnstile: {:exempt, reason}` with a non-empty reason, recorded with the root source, the calling module, and kind `:declared`.
- Library: `turnstile: {:exempt, :library}`, accepted from `Turnstile.*` callers alone, which the seam checks by reading the caller module off the stack. The outbox's markers, the relay's cursor, and the owner-role repo travel this way.

A nested call Ecto makes on the caller's behalf reuses the mediation of the call it is inside, because Ecto hands a nested association write only a few of the parent's options and `turnstile:` is not among them. `schema_migrations`, `oban_jobs`, and other framework tables declare no object type and pass under the matching rule; they need no exemption.

**The owner-role repo.** `use Turnstile.Repo, role: :owner` is the library's own channel. It runs migrations, it records nothing, and the seam treats every call on it as library-exempt. `Turnstile.Credo.UnmediatedRepo` accepts it. Under Postgres it connects as the role that owns the tables, and the migrations give that role a `SELECT` policy on every protected table, so its reads are unfiltered while its writes still meet the write gates.

**Four extension points** for an adapter, all optional: `prepare_query/3`, which the seam defines and an adapter's rewrite runs inside; the write overrides; the raw wrap; and `around_query/3`, which the seam calls for every mediated query and write, handing it the query or changeset, the decision in force, and a zero-arity function that runs the call. `turnstile_postgres` uses the fourth to open a transaction where none is open and to run `set_config/3` for the subject's session settings on every call (§4).

**The surface list and its proof.** The overrides and the seam's `prepare_query/3` are defined in a `@before_compile` hook with `defoverridable` and `super`, so they wrap whatever the application or the adapter defined, and an application's own tenancy `prepare_query` runs inside the seam's. Overrides redeclare the default argument (`opts \\ []`) so every arity routes through them. The classification is a plain list, one entry per name and arity, the shorter arities a default argument generates included. Its proof is `Turnstile.Conformance.RepoCase` (`use Turnstile.Conformance.RepoCase, repo: Example.Repo`), shipped so a thin application or an adopter runs it against its own repo: it diffs the list against the repo's exported functions, where an export outside the list fails with the function's name and arity and a repo exporting a subset of the list passes; then it calls each exported non-plumbing function with a fixture and no decision and asserts `Turnstile.Error`. The property beside it generates names and arities on and off the surface and holds each to one bucket or to none. `turnstile` pins `ecto` to the minor range the list was written against.

**Refusal.** Refusal raises `%Turnstile.Error{reason: :unmediated}`, carrying the function and its arity, the root source, the decision's object type where there was one, and the caller where the seam could read it. There is no mode that logs instead of raising.

**Change events.** A single-row write to an audited schema publishes one change event inside the write's transaction (§7, §8). A bulk write to an audited schema raises. The seam sees every write that goes through the repo, including `on_replace: :delete` and nested association writes; it cannot see a foreign key that cascades, which is why a cascade into an audited schema is a modeling decision the application makes with its eyes open.

**Static checks**, shipped in `turnstile_credo`, advisory: `Turnstile.Credo.NoRawSQL` flags `Ecto.Adapters.SQL.query*` and `Postgrex.*` calls outside an allowlist, and `Turnstile.Credo.UnmediatedRepo` flags any `use Ecto.Repo` without `use Turnstile.Repo`, the owner-role repo excepted. Nothing else: a check that every repo call carries options is a compile-time heuristic that costs more than it catches, and module-dependency boundaries are `boundary`'s job.

## §7 The two events

Two telemetry events, and the library publishes both and stores neither. Each payload carries what a consumer needs to write an OCSF record without inventing a value. The library carries the meaning; the consumer chooses the format and the schema version.

**`[:turnstile, :change]`**, published inside the write transaction, where the change is computed. Measurements are empty.

| Field | Value | What a mapper does with it |
|---|---|---|
| `operation` | `:create`, `:update`, or `:delete` | The OCSF activity |
| `kind` | `:user`, `:group`, `:role`, or `:entity`, from `audited/1` on the schema | The OCSF class |
| `target` | `{type, id}` of the row that changed | The entity type and identifier |
| `changes` | a map of field to `{old, new}`, for the fact fields that changed | The attributes before and after |
| `actor` | `{kind, id}` of the subject whose authorization allowed the write, or the library where an exemption carried it | The actor |
| `actor_kind` | `:user`, `:non_person_entity`, or `:privileged` | Whether the actor is a person or a process |
| `time` | the configured clock at the moment of the write | The event time |
| `operation_id` | one identifier shared by every event of one operation | The correlation identifier |
| `schema` | the Ecto schema module | Context a mapper may need |

**`[:turnstile, :decision]`**, published after each decision. A decision is a read, so it has no transaction. The one measurement is `duration`, in microseconds.

| Field | Value |
|---|---|
| `subject`, `subject_kind` | `{kind, id}`, and `:user`, `:non_person_entity`, or `:privileged` |
| `operation` | the operation that was asked about |
| `object` | `{type, id}`, or the query for a narrowing call |
| `verdict` | `:allow`, `:deny`, or `:scoped` |
| `reason` | an atom of `Turnstile.Answer.reasons/0` |
| `decider`, `version` | the adapter module, and its policy version string |
| `env` | the environment map as the caller gave it, with `now` stamped from the configured clock |
| `exception` | the exception, where a decider raised and the decision failed closed |
| `time`, `operation_id` | as above |

**What the consumer adds.** The class, category, severity, and type identifiers, its own product metadata, and the shape of the OCSF actor. Each of those depends on the schema version the consumer targets, and the identifiers move between versions, so they stay outside the library. `Example.Siem` maps both events to OCSF and holds the result in memory, which keeps the mapping under test without putting a schema version in any published package; `Example.Siem.schema_version/0` is what a caller reads the version through.

**What the library guarantees.**

| Id | Guarantee |
|---|---|
| E1 | A single-row write to an audited schema emits one change event, carrying every fact field that changed. |
| E2 | A bulk write to an audited schema raises and emits nothing. |
| E3 | A write that goes around the interception emits nothing. |
| E4 | A consumer that writes to the same repository from its handler joins the write transaction. |

What it does not guarantee: that a record is stored, that a handler keeps running, that the change committed, or that the old value was current at the moment of the write. The old value is the value the caller loaded. `RepoCase` asserts E1 to E4.

**Caps.** One cap, `caps[:policy_content_bytes]`, 64 KB by default, which is the policy text a version carries by value before a pointer takes its place. Every decision is published, and nothing is sampled.

**Sizes to plan against.** A decision record is 300 to 600 bytes, so a thousand port calls a second is about 86 million records a day and tens of gigabytes uncompressed. That is a log-pipeline sizing question for the adopter's consumer, and not for the library, which is the point of the split.

**Shape tests**, in the library's own suite, on every pull request, cited by nothing. They assert counts, of queries issued and of events published, because every regression that matters changes a number: a per-row telemetry call, a forgotten no-op filter, `RETURNING` on a write that needs none, a per-row `check` inside `scope`. Counts are deterministic where timings measure the runner. Query counts come from Ecto's `[:repo, :query]` telemetry with transaction-control statements filtered out. The engine's own calls are not database queries: each adapter's client publishes one telemetry event per call, which is how a shape test counts them.

## §8 Audited schemas and the change event

A schema declares what kind of thing its rows are with `audited/1`, and what its columns mean with `fact/2` and `relationship/1`. Only a change to a declared column is a change worth an event.

```elixir
defmodule Example.Assignment do
  use Ecto.Schema
  use Turnstile.Schema

  object_type(:assignment)
  audited(:role)
  # the row is the grant: the subject column, the object column, and the
  # columns that are attributes of the relationship itself
  relationship(subject: :user_id, object: :program_id, attributes: [:role])
end

defmodule Example.Marking do
  use Ecto.Schema
  use Turnstile.Schema

  object_type(:marking)
  audited(:entity)
  fact(:categories, kind: :object_attribute, object: :document_id, element: :category)
  fact(:controls, kind: :object_attribute, object: :document_id, element: :control)
  fact(:list, kind: :relationship, object: :document_id, element: :user)
end

defmodule Example.User do
  use Ecto.Schema
  use Turnstile.Schema

  audited(:user)
  fact(:employment, kind: :subject_attribute, subject: :id)
  fact(:nationality, kind: :subject_attribute, subject: :id)
end
```

`__turnstile__(:kind)` answers what `audited/1` declared or `nil`, `__turnstile__(:facts)` the `Turnstile.Schema.Fact` records in declaration order, and `__turnstile__(:relationship)` the `Turnstile.Schema.Relationship` or `nil`. A fact kind is `:subject_attribute`, `:object_attribute`, or `:relationship`; a set-valued column names the type of its elements with `element:`, so a reader of the event knows what each member of the set refers to. An audited schema need not be protected: `Example.User` above declares facts and no object type, so its writes are recorded and pass the seam without a decision.

**What one write produces.** One change event, carrying the fact fields that changed and their old and new values. The old value is the row the caller loaded, so a change a second writer made between the load and the write is not visible in the event, and the library says so rather than taking a lock to make it true.

**What raises.** `update_all`, `delete_all`, and `insert_all` on an audited schema raise `%Turnstile.Error{reason: :unmediated}` with `:bulk_write` in the detail, because one statement changing many rows has no changeset and no old value to record, and an event per row would be a lie about what the library saw. An upsert, which is any write carrying `on_conflict:`, raises for the same reason: `RETURNING` cannot say which rows were inserted and which were updated. The owner-role repo is the library's own channel and is exempt from both. An application that has a million facts to flip nightly has a modeling error rather than a missing API: something bookkeeping-shaped has been declared audited.

**The CUI mapping.** Assignment and OfficeRole rows are relationships with a `role` attribute, and a Proposal row is a relationship with a `status` attribute. The Marking's `categories`, `controls`, `releasable_to`, and `list`, and the Portion's `categories`, `controls`, and `releasable_to`, are set-valued. `User.employment` and `User.nationality` are subject attributes. `Document.decontrol`, and the columns holding the structure a graph walks, which are an office's agency, a document's program and designating office, a portion's document, a proposal's document and proposer, and an office role's account, office, and role, are object attributes. An office role is both at once: an account may hold the designator role and the approver role in one office, and each row states the one role it holds.

## §9 The outbox and the relay

An adapter whose working state is the application's own tables needs nothing here. `turnstile_fga` keeps a copy, in a store of its own, and the outbox and the relay are what keep that copy in step.

**The markers.** A handler on the change event inserts one marker row per affected object, in the transaction that changed the rows, through `Turnstile.Fga.Outbox`. What objects one change affects is the application's mapping to answer, through `changed/2`, because a change names the row it was made on and a tuple can rest on several rows at once. `Turnstile.Fga.Migration` is the helper a thin application's migration calls to create the marker table, and `Turnstile.Relay.Migration` creates the cursor table beside it. Both are in the application's own database, because a marker is written in the transaction that changed the rows and a pass advances the cursor in the transaction that delivered them.

**One pass** (`Turnstile.Relay`) is one transaction:

1. Ask for the transaction-scoped advisory lock on the runner's name. A runner told no reports the cursor, delivers nothing, and tries again after its idle interval.
2. Read the cursor, then read a batch of entries above it through the job.
3. Deliver the batch through the job.
4. Advance the cursor to the position of the last entry delivered.
5. Commit.

Delivery that fails rolls the pass back, so the cursor stays where it was and the same batch is read again. That is at-least-once delivery in position order, and a job's `deliver/3` is written for a batch it may have seen before. The runner decides only when the next pass runs: at once where the batch filled, after the idle interval where it did not, and after a wait that doubles per failure and is capped where the pass failed. A wake-up is a cast, so the process that wrote the rows is not held up by a delivery, and a wake-up arriving while a pass is already pending is dropped, because that pass reads everything committed before it runs.

**What delivery means for the store.** Per object a batch names, the drain reads what the tables require, reads what the store holds, and writes the difference, in calls of at most `Turnstile.Fga.Client.max_tuples_per_write/0` changes. Delivering a marker twice costs a read and no write, which is what lets at-least-once delivery stand as correctness. A tuple whose condition changed takes two calls, the deletion and then the writing of the same key with the new value on it, because one `Write` refuses a tuple key that appears in both its deletes and its writes. Between those two calls the store holds neither the old state nor the new one, and a pass that stops there has committed nothing, so its markers are read again.

**Telemetry.** Every pass publishes `[:turnstile, :relay, :pass]`, whether it delivered, stepped aside, or failed: measurements `delivered` and, where there was one, `position`; metadata the runner's `name`, its `job`, and either the `%Turnstile.Relay.Pass{}` or the error term the job reported.

**Beside the outbox.** `Turnstile.Fga.reconcile/0` compares the tables with the store, paged by object type, and reports what each holds and the other does not; its cost is proportional to tuples, so its interval is longer than a pass's. `Turnstile.Fga.rebuild/1` creates a store, publishes the model, writes every object the tables hold into it, and answers the new store, so a rebuild runs beside the store that is serving and the application swaps to it as a dated configuration change.

**The relay holds no authorization concept.** It names no subject, no object, and no rule, and its `lib` takes none of the library's other packages. The repo a runner is given is one whose calls carry no decision: a plain Ecto repo, or a seam repo in the owner's role. A cursor states nothing about a subject or an object, so there is nothing for a decision to cover.

## §10 The NIST line

One table, written and maintained by a person. No code reads it. Check the control numbers against the catalog before this table is published.

| Control | What holds it | Test |
|---|---|---|
| AC-3 Access enforcement | The interception and deny by default | `RepoCase`, `AdapterCase`, the `enf` scenarios |
| AC-5 Separation of duties | Rule C9 | The `sod` scenarios |
| AC-6 Least privilege | Rules C1 and C2 | The `lp` scenarios |
| AC-6(7) Review of privileges | `Turnstile.review/5`, run on a schedule, with the reports kept | `rvw-01`, `lp-08` |
| AC-2, AC-2(4) Account management | The change event. The system stores it. | The `aud` scenarios |
| AU-2, AU-3, AU-12 Audit events and content | Change events and decision events | The `aud` scenarios |
| AU-5 Audit failure alert | The telemetry handler failure event | Outside the library |
| AU-9 Protection of audit records | The store of the consumer | Outside the library |
| IA-11 Re-authentication | Rule C8, from an environment fact | The `ia` scenarios |
| Revocation | The outbox of `turnstile_fga` | `rev-01`, `rev-07` |

## §11 Toolchain pins and terms

**Toolchain pins**, verified 2026-09-07.

| Component | Version | Nix expression | Where verified |
|---|---|---|---|
| nixpkgs | `nixos-unstable`, head `c043004d…` (2026-09-05) | the flake's locked input | stable 26.05 has openfga 1.14.2, so unstable is the branch matching every pin at once |
| Erlang/OTP | 29.0.6 | `beam.packages.erlang_29` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/erlang/29.nix, same on `nixos-unstable` |
| Elixir | 1.20.4 | `beam.packages.erlang_29.elixir_1_20` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/elixir/1.20.nix (minimum OTP 27, maximum 29) |
| PostgreSQL | 18.6 | `postgresql_18`, written explicitly, never the bare `postgresql` alias | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/18.nix; the alias is 18 on unstable and 17 on both stable branches (`pkgs/top-level/all-packages.nix`) |
| OpenFGA | 1.19.0 | `pkgs.openfga` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/op/openfga/package.nix; release https://api.github.com/repos/openfga/openfga/releases/latest (published 2026-08-25) |
| Cerbos | 0.55.0 | a `stdenvNoCC` derivation that `fetchurl`s `cerbos_0.55.0_<Linux\|Darwin>_<x86_64\|arm64>.tar.gz` per system with hashes in the flake | absent from nixpkgs on every branch: https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/ce/cerbos/package.nix (404), https://github.com/NixOS/nixpkgs/issues/290460; release https://api.github.com/repos/cerbos/cerbos/releases/latest (published 2026-08-13); asset pattern from the same response, tag has `v`, filename does not |
| services-flake | active, last commit 2026-08-18 | the flake's input; `postgres` service, Cerbos and OpenFGA as process-compose processes | https://github.com/juspay/services-flake; https://community.flake.parts/services-flake/services (no cerbos or openfga service) |
| Hex: nimble_options, stream_data, boundary, styler, muontrap | 1.1.1, 1.4.0, 0.10.4, 1.12.2, 2.0.0 | `mix.lock` | https://hex.pm/api/packages/<name>; muontrap 2.0.0 is a new major, check its changelog |

Nix is not installed by the repository; a contributor installs it and the flake pins the rest. No Docker.

Each thin application's README carries the translation table from the domain's words to the adapter's: an Assignment to a `member` tuple, a marking to a policy attribute, a designator to a `WITH CHECK` role.

**Terms.** Each term belongs to the glossary of the package that owns it, and `docs/glossary-index.md` says which. What is here is the shared vocabulary, for a reader who has neither package open.

| Term | Meaning | Owner |
|---|---|---|
| Reference monitor | The part of a system that checks every access; always invoked, tamperproof, small | `turnstile` |
| Subject / object / operation / environment | Who is asking, about what, to do what, under what conditions | `turnstile` |
| Attribute | A fact about a subject or object that a rule can test | `turnstile` |
| RBAC / ABAC / ReBAC | Rules over roles / over any attribute / over relationships in a graph | `turnstile` |
| PEP / PDP / PIP / PAP | Where a request is stopped / where the answer is computed / where attributes come from / where rules are written | `turnstile` |
| Port / adapter | The interface in the library / an implementation of it for one mechanism | `turnstile` |
| Conformance suite | The tests any adapter must pass; the real contract | `turnstile` |
| Deny by default / fail closed | No unless a rule says yes / no when the system cannot decide | `turnstile` |
| Sidecar | A small server running beside the application | `turnstile_cerbos` |
| `scope` / `dynamic` | Narrow a query to what the subject may see / the Ecto where-clause fragment it returns, which can only narrow | `turnstile` |
| Scope fidelity | `scope` returns exactly the rows `check` would allow | `turnstile` |
| Row-level security | Postgres policies applied to every query on a table; `USING` for reads, `WITH CHECK` for writes | `turnstile_postgres` |
| Write gate | A rule the database enforces on inserts and updates without application code | `turnstile_postgres` |
| Mediated repo, the seam | A repo that refuses calls carrying no decision and no exemption | `turnstile` |
| Exemption | A named, recorded opt-out from mediation, per call, with a reason | `turnstile` |
| Protected schema / carried relation | A schema that declares an object type / an association the parent's decision covers | `turnstile` |
| Audited schema / kind | A schema whose single-row writes emit a change event / what its rows are | `turnstile` |
| Change event | One telemetry event for one single-row write, carrying the fact fields that changed | `turnstile` |
| Decision event | One telemetry event for one decision, carrying the verdict and the reason | `turnstile` |
| Consumer | Whatever attaches to those events and stores what it needs; not the library | `turnstile` |
| Outbox / marker / cursor | Rows written in the transaction they describe / one per affected object / how far a runner has delivered | `turnstile_fga`, `turnstile_relay` |
| Drain / reconcile / drift | Bringing a copy into step with the tables / comparing the two / a difference between them | `turnstile_fga` |
| Telemetry | Elixir's convention for a library to publish events that handlers consume | `turnstile` |
| SIEM | The security team's central log system; a sink | `example` |
| Continuous evaluation | Attributes looked up on every check, never cached across requests | `turnstile` |
| Revocation latency | Time from a revoking change to the first denial; evidence, measured | `turnstile` |
| Environment fact (port-supplied / caller-supplied) | The moment from the configured clock / facts only the caller knows | `turnstile` |
| Re-authentication | Prove it is still you before sensitive operations | `example` |
| User / NPE / privileged user | A person / software acting alone / a person who can change the system; the subject's kind | `turnstile` |
| Least privilege / separation of duties | The least access needed / dangerous combinations split between people | `example` |
| Audited override (break-glass) | Privileged access past the rules, with justification, logging, and reporting | `example` |
| CUI | Controlled unclassified information; protected by law, below classified | `example` |
| Category (Basic / Specified) | What kind of information; Specified brings its own handling rules | `example` |
| Dissemination control | Who may not receive it, below the default | `example` |
| Marking / portion marking / banner / decontrol | Categories and controls / a marking per portion / the marking every portion admits / the end of protection | `example` |
| Designating agency / lawful government purpose | Who declared it CUI / the legal basis for access | `example` |
| Redacted read | The document with the portions the subject may not read removed | `example` |
| FISMA / FIPS 199 / 800-53 / 800-53B | The law / impact levels / the catalog / the baselines | `PLAN.md` |
| Control / enhancement / family | A requirement (AC-2) / an optional sharpening (AC-2(4)) / a group (AC) | `turnstile` |
| ODP / FedRAMP-assigned parameter | A blank in a control / a blank FedRAMP fills | `turnstile` |
| Baseline / beyond baseline | The subset required at an impact level / cited but not required | `turnstile` |
| Assessment-ready | The plan's word; never "compliant", never "FedRAMP Ready" | `PLAN.md` |
| Scenario | A cited test: an id, a sentence, and the rule it tests | `turnstile`, `example` |
| Tier 1 / Tier 2 | Port guarantees over a neutral fixture / CUI scenarios per thin application | `turnstile`, `example` |
| `review` | Who can do what, today | `turnstile` |
| Thin application | One of the four applications that bind the example to an adapter | `example` |

## §12 The OpenFGA adapter

The design note for `turnstile_fga`. It began as an exercise, to find out whether the port holds where an adapter is a relationship graph, and the answer was that the port, the seam, and the events survive untouched, that three of the CUI rules come out cleaner on a graph than anywhere else, and that the costs are the kind of thing evidence exists to show.

**Zanzibar in the plan's words.** A Zanzibar-style system stores tuples, `(user, relation, object)` such as `user:alice member program:9`, and an authorization model that says how relations compose: directly assigned, computed from other relations on the same object, or followed through a related object, as in "members of the document's program". OpenFGA is the open-source implementation: a server with its own datastore, an API of `Check`, `BatchCheck`, `ListObjects`, `ListUsers`, `Expand`, `Read`, `Write`, and `ReadChanges`, models that are immutable and versioned by id, and conditions, which are small CEL expressions on tuples evaluated against a context sent with each check.

| Plan concept | OpenFGA |
|---|---|
| subject, object, operation | user, object, relation (an operation is a relation such as `can_read`) |
| environment | the `context` sent with a check, consumed by conditions |
| subject attribute | a tuple to a reified entity: `user:alice member country:US` |
| object attribute | a tuple on the object, or a condition parameter on one |
| relationship granted / revoked | a tuple written / deleted |
| policy version published | an authorization model written; its id |
| `authorize`, `check`, `batch` | `Check`, `BatchCheck` |
| `scope` | `ListObjects`, then `dynamic([d], d.id in ^ids)` |
| `review` | `ListObjects` per subject, or `ListUsers` per object |
| `explain` | `Expand`, the relation tree, which is the path explanation |
| the adapter's working state | the FGA store, a copy of what the tables say, kept in step by the outbox |
| revocation latency | commit, relay pass, engine write, check-cache TTL |

The one structural difference from the other three adapters: their working state is the application's tables, and this one keeps a copy in a store of its own. The outbox and the relay (§9) are what keep that copy in step, and `reconcile/0` is what says whether it is.

**The CUI domain as a model** (`apps/example_fga/priv/fga/model.fga`). A control on a marking is a wildcard flag, a tuple `user:* fedonly_applies document:1` meaning "this applies to everyone", and the block is the flag minus the users who clear it. Implication (C3) and portions (C4) are tuple-to-userset, so nothing is copied. Decontrol (C5) is a condition on the flag and category tuples. Separation of duties (C9) is `but not proposer`.

```
model
  schema 1.1

type user

type country
  relations
    define member: [user]

type employment
  relations
    define member: [user]

type agency
  relations
    define domestic: [country]
    define federal: [employment]
    define operator: [user]
    define domestic_member: member from domestic
    define federal_member: member from federal

type office
  relations
    define agency: [agency]
    define designator: [user]
    define approver: [user]
    define member: designator or approver
    define domestic_member: domestic_member from agency
    define federal_member: federal_member from agency
    define operator: operator from agency

type program
  relations
    define lead: [user]
    define member: [user] or lead

type category
  relations
    define fedonly_applies: [user:*]
    define noforn_applies: [user:*]

type document
  relations
    define program: [program]
    define designating_office: [office]
    define portion: [portion]
    define category: [category, category with before_decontrol]
    define listed: [user]
    define releasable_to: [country]

    define fedonly_applies: [user:*, user:* with before_decontrol] or fedonly_applies from category or fedonly_applies from portion
    define noforn_applies: [user:*, user:* with before_decontrol] or noforn_applies from category or noforn_applies from portion
    define relto_applies: [user:*, user:* with before_decontrol] or relto_applies from portion
    define list_applies: [user:*, user:* with before_decontrol] or list_applies from portion

    define lawful_purpose: member from program or member from designating_office
    define fedonly_clear: federal_member from designating_office
    define noforn_clear: domestic_member from designating_office
    define relto_clear: member from releasable_to

    define blocked_by_fedonly: fedonly_applies but not fedonly_clear
    define blocked_by_noforn: noforn_applies but not noforn_clear
    define blocked_by_relto: relto_applies but not relto_clear
    define blocked_by_list: list_applies but not listed
    define blocked: blocked_by_fedonly or blocked_by_noforn or blocked_by_relto or blocked_by_list

    define can_read: lawful_purpose but not blocked
    define can_read_redacted: lawful_purpose
    define can_change_marking: designator from designating_office
    define can_set_decontrol: can_change_marking
    define can_decontrol: can_change_marking
    define can_propose_marking: can_change_marking
    define can_override: operator from designating_office

type portion
  relations
    define document: [document]
    define category: [category, category with before_decontrol]
    define listed: listed from document
    define releasable_to: [country]

    define fedonly_applies: [user:*, user:* with before_decontrol] or fedonly_applies from category
    define noforn_applies: [user:*, user:* with before_decontrol] or noforn_applies from category
    define relto_applies: [user:*, user:* with before_decontrol]
    define list_applies: [user:*, user:* with before_decontrol]

    define fedonly_clear: fedonly_clear from document
    define noforn_clear: noforn_clear from document
    define relto_clear: member from releasable_to

    define blocked: (fedonly_applies but not fedonly_clear) or (noforn_applies but not noforn_clear) or (relto_applies but not relto_clear) or (list_applies but not listed)
    define can_read: can_read_redacted from document but not blocked
    define can_change_marking: can_change_marking from document

type proposal
  relations
    define office: [office]
    define proposer: [user]
    define can_approve_marking: approver from office but not proposer

condition before_decontrol(decontrol_at: timestamp, current_time: timestamp) {
  current_time < decontrol_at
}
```

Rule by rule. C1 is `lawful_purpose`. C2 is `can_read: lawful_purpose but not blocked`: every flag present must be cleared, and an absent flag blocks nobody. C3: a Specified category carries its own wildcard flags, and `fedonly_applies from category` inherits them, with nothing copied. C4: the document's flags include `from portion`, so a control a Portion carries applies to the document by construction on this adapter as well as at write time in the domain, while `relto_clear` is `member from releasable_to` over the document's own country tuples, which are the banner the domain narrowed to the intersection; the redacted read is `can_read_redacted` on the document and `can_read` per portion, whose `scope` is a `ListObjects` over `portion`. C5: a document with a decontrol writes its flag and category tuples with `before_decontrol` and the date, one without writes them plain, and after the date the flags evaluate false and only C1 remains. C6: `listed` is a per-document grant and combines with nothing, and the model has no path from `listed` to `lawful_purpose`. C7 is `can_change_marking`, and the write itself is gated by the seam rather than by FGA. C8, re-authentication, is not modeled: it is a fact about the session, and putting it in a condition would make every use of `designator` demand session context, so the adapter checks it from the environment before calling FGA, through the guard its binding names, as the roles adapter does through a predicate. C9 is `can_approve_marking: approver from office but not proposer`. C10 is `can_override` plus the justification and the event, in code. C11 holds per check, up to the lag of a pass. C12 is measured. C13 is `ListObjects`, by FGA's definition of it, under the cap.

**The tuple mapping** (`ExampleFga.TupleMapping`, implementing `Turnstile.Fga.TupleMapping`). Three shapes carry the whole translation. A role a row holds is a relation of the object it is held on. A subject attribute is membership of its value as an object of its own, because a graph compares by walking rather than by equality. A control that applies is the wildcard `user:*` on the relation named for it, so what a marking states is one fact about the document rather than a tuple per account.

The behaviour is four questions, and each is answered from the rows as they stand rather than from the change that arrived, because a tuple can rest on several rows at once and a change names the row it was made on: `object_types/0`, which a reconcile reads by; `objects/2`, every object of a type the tables hold; `changed/2`, which objects one change can have affected; and `tuples/2`, which tuples an object requires. What a row then states is `ExampleFga.Core.Tuples`, which reads nothing and is proved as a function of its input.

| Object | What its rows require (user · relation · object) |
|---|---|
| `agency:A` | `country:CC · domestic · agency:A` for the agency's nationality; `employment:federal · federal · agency:A`; `user:U · operator · agency:A` per account holding the override role |
| `office:O` | `agency:A · agency · office:O`; `user:U · designator \| approver · office:O`, one tuple per office-role row, so an account holding both roles holds both relations |
| `program:P` | `user:U · member \| lead · program:P` per assignment, while the program is open; a closed program requires none of them |
| `category:C` | `user:* · fedonly_applies \| noforn_applies · category:C` for the controls the category implies |
| `country:CC`, `employment:E` | `user:U · member · country:CC`; `user:U · member · employment:E`, from each account's nationality and employment |
| `document:D` | `program:P · program · document:D`; `office:O · designating_office · document:D`; `category:C · category · document:D` and `user:* · <control>_applies · document:D` from the marking, each carrying `before_decontrol` where the document has a decontrol date; `country:CC · releasable_to · document:D`; `user:U · listed · document:D` per account the DL ONLY list names |
| `portion:X` | `document:D · document · portion:X` and `portion:X · portion · document:D`; the portion's own categories, controls, and countries, carrying the document's decontrol date |
| `proposal:P` | `office:O · office · proposal:P`; `user:U · proposer · proposal:P` |

A tuple is identified by its user, its relation, and its object, and a condition is a value carried on it rather than part of that identity. That is what makes a changed decontrol date a delete and a write of one key rather than a second tuple, and why it takes two calls (§9).

**The client and its fake.** `Turnstile.Fga.Client` is the only path to the server: `create_store/2`, `write_model/3`, `check/3`, `batch_check/3`, `list_objects/3`, `expand/3`, `read/3`, and `write/3`, each answering a value or a `%Turnstile.Error{reason: :engine_unreachable}`, none of them raising. The endpoint comes first, the store second, and a request struct per call third, because a model id and a consistency are values on a request rather than state on the client: a decision is taken under a version. `Turnstile.Fga.Client.Fake`, in test support, is the same behaviour on an `Agent`, and it copies what a caller can get wrong: a write is atomic per call, and a duplicate write, a delete of a tuple the store does not hold, a tuple key on both sides of one call, and more changes than one call may carry each change nothing at all. It does not evaluate the model, so what it answers questions from is the tuples it holds directly, in the types the real client answers in.

**Decisions and scope.** `Check` with the model id pinned per request and `consistency` set per operation: `HIGHER_CONSISTENCY` for anything under C7 to C10, `MINIMIZE_LATENCY` allowed for reads. The decision event carries the model id as its policy version. `ListObjects` returns ids, so `scope` is `dynamic([d], d.id in ^ids)`; above the cap the port falls back to `filter` per page with `BatchCheck`, and scoping the query to a tenant first keeps most lists under the cap.

**What the package proves, and where.** `Turnstile.Fga.Core.Drain` holds the arithmetic of a difference and is proved by a property over generated held and required sets. `Turnstile.Fga.Core.Codec` is the tuple encoding, proved by a property that holds a condition's values to the values that were encoded. Three templates hold an application's binding to what a decision rests on: `Turnstile.Fga.TupleMappingCase` for the mapping it declares, `Turnstile.Fga.OutboxCase` for the drain it runs, which is where the drift scenario is, and `Turnstile.Fga.GuardCase` for the guard it names.

## §13 Test environment and conformance

See `docs/testing.md` for how a run is set up. A Nix flake pins the toolchain (§11) and provides the Postgres, Cerbos, and OpenFGA binaries; a run starts an ephemeral cluster of its own, with two roles, `turnstile_owner`, which owns the tables and runs migrations, and `turnstile_app`, which does not own them and carries `NOBYPASSRLS` (§4). Every test owns its state, so `async: true` is the default, and the tagged exceptions are the tests that need a committed database.

**The neutral fixture and the conformance artifacts.** Tier 1's fixture is the library's own: two object types, two roles, one attribute, one relationship, as Ecto schemas against the same Postgres the rest of the suite uses. Each adapter package carries what that fixture needs on its own mechanism, in its own `test/support`, under a `Conformance` module of the package's namespace: `turnstile_postgres` the row-level security migration for the fixture tables, `turnstile_cerbos` the attribute declarations, `turnstile_fga` the tuple mapping, and `turnstile_rbac` the role table and predicates. What an engine reads as text rather than as a compiled module stays under `priv/conformance/`, which is the Cerbos policies and the OpenFGA model. `Turnstile.Conformance.AdapterCase` takes the adapter through the configuration override, so all four run in one `mix test` as async modules.

**The case templates.**

| Template | What it holds to | Package |
|---|---|---|
| `Turnstile.Conformance.AdapterCase` | The port's invariants as `stream_data` properties over generators the adapter's test module supplies: scope fidelity, deny by default, batch agreement | `turnstile` |
| `Turnstile.Conformance.RepoCase` | The surface list against a repo's exports, a refusal from every non-plumbing call without a decision, and E1 to E4 | `turnstile` |
| `Turnstile.Conformance.Case` | The `scenario` macro: a `test` whose name is the sentence, tagged with the id, the rule, and the controls §3a cites, each checked against `Turnstile.Conformance.Scenarios` at compile time | `turnstile` |
| `Turnstile.Relay.JobCase` | The three obligations a runner relies on from a job, over a population module the job supplies | `turnstile_relay` |
| `Turnstile.Fga.OutboxCase`, `GuardCase`, `TupleMappingCase` | The drain, the guard, and the mapping a binding declares | `turnstile_fga` |

**The scenario macro.** `scenario "enf-01", "<sentence>", rule: :c1 do ... end`. The id, the sentence, and the rule are checked against `Turnstile.Conformance.Scenarios`, which holds §3a's table as data, and the freeze test holds that module to this document. The count test each thin application defines last reads the ids off the tests the module defined, so a scenario that is never written is a failure rather than a silence. No binding declares a scenario unsupported: every scenario runs under every binding.

**Declared-fact coverage**, one case per adapter whose rules read columns: every column an adapter's rules read is a declared fact (§8). For `turnstile_rbac` and `turnstile_cerbos` the case walks the `dynamic` that `scope` returns, subqueries included, and collects every field reference against the schema it belongs to; for `turnstile_postgres` it reads the policy predicates from `pg_policy` and collects the column references. A column counts as declared where a `fact` or `relationship` declaration on its schema names it, as the fact column, the subject column, or the object column, and the primary key and the foreign key of a carried relation are references to the object and count as declared. A rule that reads an undeclared column fails the case with the column's name, because a change to that column would move a decision and emit nothing.

**Schema dump.** `mix turnstile.schema_dump`, a task in `turnstile`, dumps `pg_dump --schema-only` after migrations into `priv/schema/<adapter>.sql`, and each thin application's CI job fails on a diff against the committed file. The task reads the repo, the output path, and the migrations from the `:turnstile` key of the application's Mix project. The Postgres one is the teaching artifact: it is where the row-level security policies are legible as SQL.

## §14 The configuration struct

`%Turnstile.Config{}` is validated once at boot from a `NimbleOptions` schema and is the only runtime configuration the library reads. It is put in `:persistent_term` at boot, and read from there. Tests override any field through `Turnstile.Test.with_config/1`, which puts the override in the process dictionary, and the resolver checks `self()` and then the `$callers` chain.

| Field | Type | Default |
|---|---|---|
| `adapter` | `module \| {module, keyword}`, the module implementing `Turnstile.Adapter` and its options, validated by the adapter's own `options_schema/0`; a bare module means `[]` | required |
| `clock` | `(-> DateTime.t())`, a zero-arity function answering the current time in UTC | `&DateTime.utc_now/0` |
| `caps` | keyword, one key: `policy_content_bytes`, the policy text a version carries by value | `[policy_content_bytes: 65_536]` |

Adapter options by adapter: `turnstile_cerbos` takes an `address`; `turnstile_fga` takes an `endpoint`, a `store_id`, a `model_id`, and a `client`, which is the behaviour's implementation and is the fake in tests; `turnstile_rbac` and `turnstile_postgres` take none, so their entry is the bare module. The consistency per operation and the `ListObjects` cap are constants of `turnstile_fga` rather than options. How often a relay pass runs belongs to the runner a thin application starts, not to this struct.
