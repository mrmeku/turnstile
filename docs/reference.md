# Turnstile: reference notes for plan v9
*Tables, numbers, and mechanics the plan cites by section. Nothing here is a decision the plan does not already make; this is where the plan's decisions are spelled out at implementation grain. Section numbers are the plan's; §3a and §15 are the newest. Each section moves into the docs of the package that owns it as that package appears. ⟨verify⟩ marks a claim to check against the standard cited or the pinned Ecto before relying on it.*

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

**The portion**. `Portion(document_id, marking: Marking)` is a row under `Document`; a document may have none. The document's marking is its banner, the union of its portions' markings (C3 rule C4, enforced at write time in the domain). `Portion` declares its own object type, is not a carried relation of `Document`, and its `marking` is a fact field of kind `:object_attribute`.

Two read operations on a document. `read` is the whole document under the banner: a Document decision under C1 and C2 over the banner. `read_redacted` returns the document with the portions the subject may not read removed: a Document decision under C1 (`authorize(subject, :read_redacted, document)`), then a Portion `scope` (`scope(subject, :read, Portion)`) whose `dynamic` the seam applies to the portions query, `Repo.preload(document, :portions, turnstile: portion_decision)`. Because `Portion` is not carried, a preload without its own decision is refused (§6). Scope fidelity (C13) holds at portion level: the portions returned are exactly those for which `check(subject, :read, portion)` is true. Each adapter filters portions as rows of their own under a policy of their own:

| Adapter | Portion mechanism |
|---|---|
| `turnstile_rbac` | a `read` operation on `Portion` whose predicates are the document predicates over the portion's marking |
| `turnstile_postgres` | a second row-level security policy on the `portions` table; the `documents` policy is not consulted for portion rows |
| `turnstile_cerbos` | a `portion` resource kind with its own policy; `scope` over portions with derived markings falls back to `filter` (§3) |
| `turnstile_fga` | a `portion` type with a `document` parent, the control flags on the portion, and `can_read: lawful_purpose from document but not blocked` (§13) |

## §3 Rules and mechanisms

The rules move to the example's glossary as `turnstile_example` appears.

| Rule | Statement |
|---|---|
| **C1 Lawful purpose** | `read` on a Document requires an Assignment to its Program or an OfficeRole in its designating Office. |
| **C2 Controls, all of** | Every Control on the effective marking is a test on the subject, and all must pass. |
| **C3 Specified categories** | A Specified category adds its implied Controls. Effective controls are declared ∪ implied. Nothing is copied. |
| **C4 Banner** | A Document's marking is the union of its Portions' markings, enforced at write time in the domain and tested as a scenario. A change to a Portion's marking recomputes the banner in the same transaction; a Document marking that would drop a Portion's control is refused. |
| **C5 Decontrol** | After the decontrol date or event, C2 to C4 no longer apply; C1 still does. The current time is a port-supplied environment fact. |
| **C6 Named list is a direct grant** | `named_list` membership is per Document per User and combines with nothing; it never overrides C1. |
| **C7 Marking gates** | Changing a marking, setting a decontrol, or decontrolling requires a `designator` role in the designating Office. |
| **C8 Re-authentication** | C7 operations additionally require the session to have re-authenticated within a configured window. |
| **C9 Separation of duties** | A marking change proposed by one designator must be approved by a different approver. |
| **C10 Audited override** | A privileged user holding the override permission may read a Document outside C1 with a justification; the read succeeds, always emits its own event, and is reported to the designating Office. Never unconditional. |
| **C11 Continuous evaluation** | Assignments, list membership, employment, and nationality are evaluated at every check; a change deletes nothing. |
| **C12 Revocation clock** | A revoked fact is enforced within the configured maximum delay. The measured latency is recorded beside the configured maximum; no test asserts it. |
| **C13 Scope fidelity** | `scope` returns exactly the rows for which `check` is true, for Documents and for Portions. |

**Mechanism per rule per adapter.** The source of each cell is the thin app's capability declaration (`example_<adapter>`, the function clauses below); this table is what the plan expects each thin app to declare, so a declaration that differs from it is a finding for the stage that wrote it. A level in parentheses is `native` unless written.

| Rule | `example_rbac` | `example_postgres` | `example_cerbos` | `example_fga` |
|---|---|---|---|---|
| C1 | predicate with subqueries over Assignment and OfficeRole in the `dynamic` | `USING` policy on `documents` with `EXISTS` subqueries over `assignments` and `office_roles` against `current_setting('turnstile.subject_id')` | policy condition over the declared attributes `program_roles` and `office_roles`, both subqueries selecting the role held over the row | `lawful_purpose` relation |
| C2 | one predicate per control, conjoined | the same policy's predicate over the marking tables, reading `employment` and `nationality` from `users` at every call | one policy rule per control over sent subject attributes | `can_read: lawful_purpose but not blocked` |
| C3 | implied controls read from `categories` in a subquery | the policy joins `categories` | `check` and `scope` over the attribute `effective_controls`, a subquery that derives declared ∪ implied outside the policy (limited) | `fedonly_applies from category` and the other flags, nothing copied |
| C4 | the union enforced in `Example.Documents` at write time; a `read` on `Portion` for the redacted read | the union in the domain; the second policy on `portions`, which reads the document's program, office, and decontrol through `SECURITY DEFINER` accessors so the document's own policy does not narrow it | the union in the domain; the `portion` resource kind, whose decontrol is the document's and so is tested inside its subqueries (limited) | the union in the domain; `from portion` on the document's flags, the `portion` type for the redacted read |
| C5 | the port's clock compared in the predicate | `current_setting('turnstile.now')` set by `around_query/3` | `now` sent as a request attribute from the port's clock | the `before_decontrol` condition with `current_time` in the check context |
| C6 | membership of the marking's list in a subquery | the policy over the marking's `list` column | the attribute `listed`, a subquery | `listed` with the `list_applies` flag |
| C7 | the seam refuses the write without a `change_marking` decision; the predicate tests the OfficeRole (by the seam) | `WITH CHECK` policy on `documents` and `markings` requiring a designator row; the refusal needs no application code, printed as a defense-in-depth note (by the database) | the `change_marking` action's policy requires `designator`; the write is gated by the seam (by the seam) | `can_change_marking`; the write is gated by the seam (by the seam) |
| C8 | the adapter reads `reauthenticated_at` from the environment before the rules (by the adapter) | `current_setting('turnstile.reauthenticated_at')` inside the `WITH CHECK` predicate | sent as a request attribute; the policy compares it with the window | the adapter checks it from the environment before calling the server (by the adapter) |
| C9 | a predicate requiring the approver and the proposer to differ | `WITH CHECK` on `marking_proposals` comparing `proposer_id` with the subject setting | policy condition over `proposal.proposer_id` | `can_approve: approver from office but not proposer` |
| C10 | the privileged path in `Example.Documents.override_read/3`: permission, justification, event, report (by application code) | the read runs under a declared exemption, which the exempt policy of the application role admits; permission, justification, event, and report in application code (by application code) | an `override` action for the `privileged` principal kind; justification, event, and report in application code (by application code) | `can_override`; justification, event, and report in application code (by application code) |
| C11 | predicates read the tables at every check | policies evaluate at execution | facts are sent with each request | every `Check` walks current tuples, up to the projector's lag |
| C12 | measured; evidence, never a level (§4) | measured | measured | measured, drain included |
| C13 | the `dynamic` is the rule | row-level security is the rule; `scope` returns `true` | the query plan compiled to a `dynamic`; an expression the compiler does not carry fails closed (limited) | `ListObjects` under the cap; `filter` per page above it (limited) |

Where the adapters differ on these. Write gates without application code: Postgres only, a C7-violating marking change is refused by the database whether or not the application asked; this is not a rule, it is a defense-in-depth property of Postgres. Rules owned by non-developers, versioned and tested as their own artifact: Cerbos only. Explanation: Cerbos names the matched rule, code names the clause, OpenFGA returns the path from `Expand`, Postgres names nothing. Derived markings (C3, and C4 through portions): Cerbos plans over the attributes it is sent alone, so the derivation lives in the subquery a declaration names rather than in the policy, and the thin app records limited; nothing is materialized; OpenFGA walks them as tuple-to-userset with nothing copied. Request-time facts (C5, C8): native everywhere, Postgres threads them through session settings, OpenFGA takes C5 as a tuple condition with the time in the check context and takes C8 in the adapter, from the environment, before the call. OpenFGA alone: C9 is `approver from office but not proposer`; `scope` is `ListObjects`, capped, declared limited. The model and the tuple mapping are in §13.

**Capability levels and records**. Three levels: `native`, `limited`, `unsupported`. A rule enforced by another component of the same stack (C7 by the seam under RBAC, Cerbos, and OpenFGA; C8 by the adapter under OpenFGA) is `native` with the enforcing component named. Only `unsupported` skips a scenario; `limited` carries its note in the test's tags. The record is `{level, by: component, note: String.t()}` where `component` is one of `:adapter`, `:seam`, `:database`, `:engine`, `:application`. A thin app's declaration is one function clause per record plus a fallback, never a map lookup:

```elixir
defmodule ExampleCerbos.Capabilities do
  @behaviour Turnstile.Capabilities

  @impl true
  def capability(:c3), do: {:limited, by: :engine, note: "the implied controls are derived in the subquery the declaration names"}
  def capability(:c4), do: {:limited, by: :engine, note: "a portion's decontrol is its document's, so the controlled test is in the subquery"}
  def capability(:c7), do: {:native, by: :seam, note: "the write is refused by the seam before the policy is asked"}
  def capability(:c10), do: {:native, by: :application, note: "permission, justification, event, and report in code"}
  def capability(:c12), do: {:native, by: :adapter, note: "the latency is measured and recorded, never asserted"}
  def capability(:c13), do: {:limited, by: :engine, note: "scope holds where the plan compiles, and any other expression fails closed"}
  def capability(_rule), do: {:native, by: :engine, note: ""}
end
```

Tier 2 runs once per thin app; the count test (`docs/testing.md` §6) checks every skip against this declaration.

## §3a Tier 2 scenarios

Frozen at S1 with the contracts. Every row is a test in `Example.Scenarios` whose name is the sentence, declared with the `scenario/4` macro (`scenario "enf-01", "<sentence>", control: [...], rule: :c1 do ... end`, §14), run by each thin app. "Tests" names the C-rule, or the guarantee where the scenario tests the port or seam in the domain's words. "Needs" is `ledger` where a mode-none run skips the scenario with `:needs_ledger`; a blank means it runs in both modes. Beyond-baseline citations are marked with an asterisk.

| Id | Sentence | Group | Controls cited | Tests | Needs |
|---|---|---|---|---|---|
| `enf-01` | A User with an Assignment to a Document's Program reads it | enforcement | AC-3 | C1 | |
| `enf-02` | A User with neither an Assignment nor an OfficeRole is denied the Document | enforcement | AC-3 | C1 | |
| `enf-03` | A User holding an OfficeRole in the designating Office reads a Document of that Office's Program without an Assignment | enforcement | AC-3 | C1 | |
| `enf-04` | A contractor is denied a FED ONLY Document they are assigned to | enforcement | AC-3, AC-16* | C2 | |
| `enf-05` | A foreign national is denied a NOFORN Document of a domestic Agency | enforcement | AC-3 | C2 | |
| `enf-06` | A User whose nationality is outside the REL TO list is denied the Document | enforcement | AC-3 | C2 | |
| `enf-07` | A User on the DL ONLY list reads the Document and one not on it is denied | enforcement | AC-3 | C2, C6 | |
| `enf-08` | A Document carrying two controls is denied to a User who clears one of them | enforcement | AC-3 | C2 | |
| `enf-09` | A Specified category's implied control blocks a User the declared controls would allow | enforcement | AC-3 | C3 | |
| `enf-10` | A Document with no controls is read by any User with a lawful purpose | enforcement | AC-3 | C2 | |
| `enf-11` | A NOFORN Portion is removed from a foreign national's redacted read while the rest of the Document returns | enforcement | AC-3 | C4, C13 | |
| `enf-12` | A Document marking that would drop a Portion's control is refused at write time | enforcement | AC-3, AC-16* | C4 | |
| `enf-13` | After the decontrol date a contractor reads a FED ONLY Document they are assigned to | enforcement | AC-3 | C5 | |
| `enf-14` | Before the decontrol date, by the port's clock, the same Document is denied | enforcement | AC-3 | C5 | |
| `enf-15` | A decontrolled Document is still denied to a User with no lawful purpose | enforcement | AC-3 | C5, C1 | |
| `enf-16` | DL ONLY membership without an Assignment does not grant the read | enforcement | AC-3 | C6 | |
| `enf-17` | The Documents `scope` returns are exactly the Documents `check` allows, over random subjects | enforcement | AC-3, AC-25* | C13 | |
| `enf-18` | The Portions `scope` returns are exactly the Portions `check` allows | enforcement | AC-3 | C13 | |
| `enf-19` | A Document of another Agency is neither returned by `scope` nor readable by `check` | enforcement | AC-3 | C1, C13 | |
| `lp-01` | A Program member without an OfficeRole cannot change a Document's marking | least privilege | AC-6, AC-6(1) | C7 | |
| `lp-02` | A designator of another Office cannot change the marking | least privilege | AC-6(1) | C7 | |
| `lp-03` | A designator of the designating Office changes the marking | least privilege | AC-6(1) | C7 | |
| `lp-04` | Setting a decontrol needs a designator | least privilege | AC-6(1) | C7 | |
| `lp-05` | A Portion's marking change needs a designator of the Document's designating Office | least privilege | AC-6(1) | C7, C4 | |
| `lp-06` | An ordinary account cannot invoke the override | least privilege | AC-6(10) | C10 | |
| `lp-07` | A privileged account is a separate account: the same person's ordinary account cannot override | least privilege | AC-6(2) | C10 | |
| `lp-08` | `mix turnstile.review` lists every privileged account and every permission a role holds | least privilege | AC-6(5), AC-2(7) | C7, C10 | |
| `sod-01` | A marking change proposed by a designator is approved by a different approver | separation of duties | AC-5 | C9 | |
| `sod-02` | The proposer, who is also an approver, cannot approve their own proposal | separation of duties | AC-5 | C9 | |
| `sod-03` | A proposal without approval does not change the marking | separation of duties | AC-5, CM-5 | C9 | |
| `rev-01` | A revoked Assignment denies the next check; the measured latency and its components are recorded, never asserted | revocation and expiry | AC-2, PS-4, AC-3(8)* | C11, C12 | |
| `rev-02` | Removal from a DL ONLY list denies the next read | revocation and expiry | AC-2, AC-2(1) | C11 | |
| `rev-03` | A change of employment from federal to contractor denies a FED ONLY read at the next check | revocation and expiry | AC-2, PS-5 | C11 | |
| `rev-04` | A corrected nationality applies at the next check | revocation and expiry | AC-2, AC-16* | C11 | |
| `rev-05` | A closed Program revokes every Assignment's lawful purpose at the next check | revocation and expiry | AC-2, AC-2(3) | C11 | |
| `rev-06` | A tightened rule, published as a policy version, is enforced within the measured propagation, which is recorded | revocation and expiry | AC-2, CM-3 | C12 | |
| `rev-07` | A revocation deletes nothing but the fact: the Document, the Program, and the history remain | revocation and expiry | AC-2(4) | C11 | ledger |
| `aud-01` | Every Document read emits one decision event carrying subject, object, operation, verdict, reason, policy version, and positions | decision audit | AU-2, AU-3, AU-12 | every call is evented | |
| `aud-02` | A denied read emits its event with the reason | decision audit | AU-2, AU-3 | every call is evented | |
| `aud-03` | A decision record carries no attribute value | decision audit | AU-3 | record shape | |
| `aud-04` | A marking change emits one decision event and one fact event per changed fact field in the same transaction | decision audit | AU-12, AC-2(4) | no fact without an entry | ledger |
| `aud-05` | A bulk re-marking of N Documents emits one audit record and N fact events sharing an operation id | decision audit | AU-12, AC-2(4) | per operation, never per row | ledger |
| `aud-06` | An Assignment grant and its revoke each produce a fact event carrying old and new | decision audit | AC-2(4) | the fact mapping | ledger |
| `aud-07` | The example store's chain verifies, and a rewritten record breaks every hash after it | decision audit | AU-9, AU-9(4) | the chained store | |
| `aud-08` | A rolled-back write leaves no fact event and no decision outcome but the exception span | decision audit | AU-2, AU-12 | atomicity | ledger |
| `rvw-01` | `mix turnstile.review` lists who can read what today, per Agency | access review | AC-2, AC-6(7) | `review` | |
| `rvw-02` | With a ledger, review on a past date equals the fold stopped there | access review | AC-2, AC-6(7) | replay | ledger |
| `rvw-03` | Replay reproduces a recorded decision from its applied position and policy version | access review | AC-2, AC-6(7) | replay | ledger |
| `rvw-04` | An Assignment inserted outside the seam is reported by reconcile within the interval | access review | AC-2, AC-2(4) | drift | ledger |
| `ia-01` | A designator whose session re-authenticated within the window changes a marking | re-authentication | IA-11 | C8 | |
| `ia-02` | A designator whose session is older than the window is refused until re-authentication | re-authentication | IA-11 | C8 | |
| `ia-03` | A marking change with no re-authentication fact supplied is denied | re-authentication | IA-11 | C8 | |
| `ovr-01` | A privileged user with the override permission reads outside C1 with a justification, and the read emits its own event and is reported to the designating Office | emergency override | AC-6(9), AU-6 | C10 | |
| `ovr-02` | Without a justification the override is denied | emergency override | AC-6(9) | C10 | |
| `ovr-03` | The override never reaches C7: a privileged user cannot change a marking through it | emergency override | AC-6(9), AC-6(1) | C10, C7 | |
| `cm-01` | Every policy-version event names its author and its approval | change control on policy | CM-3, CM-5 | policy versions | ledger |
| `cm-02` | A decision made under version N carries N after version N+1 is published | change control on policy | CM-3 | policy versions | ledger |
| `cm-03` | A rule change is a policy version whose event names the artifact it is on this adapter | change control on policy | CM-3 | policy versions | |

No scenario tests "write gates without application code"; it is not a rule.

## §4 Adapters: comparison, declarations, notes, latency

| Adapter | Package | Enforcement | Explains | Revocation latency components | Rules live in | Boundary cost |
|---|---|---|---|---|---|---|
| RBAC in code | `turnstile_rbac` | the application's discipline, backed by the seam | the clause | commit | Elixir modules; a deploy is a policy version | none |
| Postgres row-level security | `turnstile_postgres` | the database; write gates need no application code (a printed note, not a rule) | verdict only | commit | migrations; a migration is a policy version | none new |
| Cerbos | `turnstile_cerbos` | the application's discipline; policies versioned and tested as their own artifact | verdict and matched rule | commit for facts; policy propagation (the poll interval) for rules | policy files; a policy owner | one sidecar |
| OpenFGA | `turnstile_fga` | the application's discipline, backed by the seam; the graph decides | the path (`Expand`) | commit, projector drain, engine write, check-cache TTL for facts; model publication for rules | a model file in a repository, published as an immutable model id; tuples projected from the ledger | a server and a datastore: two inventory items, one engine if the datastore shares the application's Postgres instance |

**Declarations, in two places**. An adapter package declares only what is true of it in any domain: `requires_ledger` (boolean) and `scope_cap` (an integer or `:none`). It also ships `priv/conformance/` for Tier 1's neutral fixture (§14). The thin app declares the capability per rule, C1 to C13, as §3's function clauses, and, in its README, the translation table from the domain's words to the adapter's. Measured revocation latency is in neither declaration; it is evidence (below).

- **Postgres.** The application role must not own the tables, or row-level security is bypassed, and it carries `NOBYPASSRLS`; `FORCE ROW LEVEL SECURITY` on every protected table. Forcing it applies the policies to the owner as well, so the migrations give the owner role a `SELECT` policy on every protected table, which is what reconcile, genesis, and the accessor functions read through. Session settings are set inside `around_query/3`: the adapter opens a transaction where none is open, one per call, and runs `set_config(name, value, true)` for `turnstile.subject_id`, `turnstile.subject_kind`, `turnstile.operation`, `turnstile.now`, and one name per fact the caller supplied, such as `turnstile.reauthenticated_at`, so two subjects in one transaction each set their own; policies read them with `current_setting(name, true)`. Where the transaction was already open when the call arrived, the adapter puts the names it set back to the empty string as the call returns, so a query the seam admits outside a decision is not read under the settings of the last one. `check` for a write operation is a `SELECT` of the update policy's `USING` predicate, read from `pg_policy` at boot and cached per policy version, run against the target row under those settings; `authorize(subject, :change_marking, document)` answers before the write this way, and the write itself is then refused or admitted by `WITH CHECK`. A thin application that writes `USING (true)` on a gate moves the whole decision into `WITH CHECK`, so a write no one asked about raises instead of matching no row, and the `SELECT` policy of the operation is what narrows the answer. An RLS `scope` decision record carries rule `true`, the migration number as policy version, and a hash of the session settings in force (§7). The policy expressions are read back from `pg_policy` for the policy-version event. The `replica_lag` component prints "not measured": v9 configures no replica. Portions: a second policy on `portions`. Replay for this adapter means state and policies in a scratch database. The per-rule table is `example_postgres`'s (§3).
- **Cerbos.** Facts arrive with each request, so their latency is one request; rules arrive on the sidecar's policy poll interval, which is the latency for policy changes, measured from a policy publish. A sidecar picking a version up is measured as propagation latency, not ledgered. The sidecar's decision logs are reconciled with the port's decision events; any difference is a drift scenario. Its `version` field on a policy runs variants side by side and is not history; history is the policy repository's commit. An attribute declaration maps a Cerbos attribute name to a column or to a subquery, and the query plan is compiled to a `dynamic` over declared attributes only; a plan over an attribute declared as a subquery becomes `in subquery(...)`, and a plan the compiler cannot express falls back to `filter` with the thin app recording limited:

  ```elixir
  attribute :nationality, column: :nationality
  attribute :employment, column: :employment
  attribute :program_roles, subquery: &Example.Assignments.program_roles_for/1
  attribute :effective_controls, subquery: &Example.Markings.effective_controls_for/1
  ```

  Portions are a `portion` resource kind with its own policy. Replay is the cheapest of the four: fold facts to the date, check out the policies at the commit, start a throwaway sidecar.
- **RBAC in code.** The role→permission table is declared data; attribute predicates are functions in the same modules. Portions get a `read` operation of their own. The boot-time policy-version append runs inside a transaction that takes the counter row (§9), so it cannot race across nodes; in ledger mode none it emits telemetry only. Replay of the predicates needs the commit, so replay of RBAC rules depends on the repository's retention.
- **OpenFGA.** Requires a ledger. The adapter talks to the server only through the `Turnstile.Fga.Client` behaviour, and an `Agent`-backed fake client in test support is built first (§13). The projector drains fact events from the ledger's reader from a checkpoint, applies the tuple mapping, and writes in batches (default `maxTuplesPerWrite` 100 on the pinned server, counting the deletes and the writes of one call together); it advances its checkpoint in the application's database after every acknowledged `Write` call; the drain computes, per touched object, the difference between the tuples the fold requires and what `Read` returns, writes only that difference, and tolerates no errors, so a re-drain after a crash converges (a Tier 1 case on the committed repo). `rebuild/1` takes the projector's configuration, creates a store, publishes the pinned model, folds from position zero into it, and returns the new store id; serving continues from the old store until the application swaps `store_id` in config, a dated configuration change; minutes for a million facts, beside the serving store, then a swap. Reconcile compares the fold with `Read`, paged by type; cost is proportional to tuples, so the interval is longer. `Check` pins the model id and sets `consistency` per operation: `HIGHER_CONSISTENCY` under C7 to C10, `MINIMIZE_LATENCY` allowed for reads, a constant of the adapter; the check cache, if enabled, adds its TTL to latency. `ListObjects` has a result cap of 1,000, a constant of the adapter and deadline on the order of a thousand ⟨verify⟩; above it the seam falls back to `filter` per page with `BatchCheck`. Self-hosted means the open-source server; a hosted FGA is a hosted engine and inadmissible. Portions are a `portion` type with a `document` parent. Replay: fold to the date, write the tuples into a throwaway server with the in-memory datastore, pin the model in force then (models are immutable and kept) and `Check`.

**Revocation latency as evidence**. One Tier 1 case per adapter, `@tag :committed`, from the template in core. It writes a revoking fact through the seam on the committed repo, reads `System.monotonic_time(:millisecond)` when the transaction returns, polls the port with `Turnstile.Test.poll/2` until the first denied check, and reads the clock again. The number and its components are printed to the log, with the poll interval as the measurement's floor. Components: `commit` (every adapter, the elapsed time above); `projector_drain` (`turnstile_fga`, from the revoking event's position to the checkpoint advance that covers it); `policy_propagation` (`turnstile_cerbos`, from a policy publish to the first denial under the new policy); `replica_lag` and `cache` (printed "not measured", since v9 configures neither a replica nor a cache). The total is what a reader compares with the FedRAMP-assigned PS-4 value ⟨verify⟩; nothing asserts it.

## §5 Policy-version events

A policy version is the fourth fact kind, `%Turnstile.FactEvent{kind: :policy_version}`. Its payload: `subject_ref` is `nil`; `object_ref` is `{:policy, adapter}`; `attribute` is `:version`; `old` is the previous version identifier or `nil`; `new` is `%Turnstile.PolicyVersion{adapter, version, content_hash, content, pointer, author, approval, at}`, where `content` is the text by value only when it is under `caps[:policy_content_bytes]` (64 KB default) and `pointer` names the store it lives in otherwise. Decision records carry the version identifier and never content. One event per version, never per node, boot, or sidecar.

| Adapter | Version | Appended by | Carries | Getting an old version back |
|---|---|---|---|---|
| RBAC in code | the commit or release | the application at boot, inside a transaction that takes the counter row, only when the ledger head names an older version; telemetry only in mode none | commit, hash of the rule modules, the role→permission table as data when under the cap | check out the commit; run that release's port |
| Postgres | the migration number | the migration, in the same transaction as its DDL | `USING` and `WITH CHECK` expressions read from `pg_policy`, self-contained | apply that migration's policies to a scratch database |
| Cerbos | the policy repository's commit | the policy repository's CI on merge | commit, hash of the files, the files when under the cap | a throwaway sidecar over the files at that commit |
| OpenFGA | the model id the server returns on publish, with the model repository's commit | the model repository's CI on publish | model id, commit, hash of the model file, the DSL text when under the cap | pin the model id (models are immutable and kept) over tuples folded to the date in a throwaway server |

## §6 The Repo seam: surface, matching, exemptions, mechanics, checks

`use Turnstile.Repo` after `use Ecto.Repo`; the macro raises at compile time if the order is wrong. The failure mode to defend against is silent: a function core forgot to wrap runs unmediated.

**Classification** (`Turnstile.Repo.Surface`), every `Ecto.Repo` function in exactly one bucket:
- *query*: mediated through `prepare_query/3`: `all`, `all_by`, `one`, `get`, `get_by`, `reload`, `aggregate/3` and `/4`, `exists?`, `stream`, `preload`, `update_all`, `delete_all`, and the raising variant of each.
- *write*: overridden: `insert`, `update`, `delete`, `insert_or_update`, `insert_all`, the raising variant of each, and every one of them called with `on_conflict:`, which is an upsert; an upsert on a fact schema is refused.
- *raw*: wrapped to demand an exemption: `query`, `query_many`, and the raising variant of each.
- *plumbing*: touches no rows: `transaction`, `transact`, `rollback`, `in_transaction?`, `checkout`, `checked_out?`, `config`, `start_link`, `stop`, `child_spec`, `load`, `get_dynamic_repo`, `put_dynamic_repo`, `default_options`, `prepare_query`, `prepare_transaction`, `to_sql`, `explain`, `disconnect_all`, `__adapter__`, and the seam's own `__turnstile__`, which answers the repo's role.

**Matching**. A schema is protected iff it declares an object type. Three rules decide which decision applies to which query:
1. The seam judges a query by its root source. A query whose root source is a protected schema and whose decision names a different object type is refused.
2. A preload or association query needs its own decision unless the parent schema declares the association as a carried relation; a nested association write of another protected schema is refused unless that association is carried.
3. A multi-source query is judged by its root source, and every other protected source in it must be carried by the root.

Queries on unprotected schemas pass without a decision. The declarations sit in the schema module beside the fact mapping, from the same macro:

```elixir
defmodule Example.Document do
  use Ecto.Schema
  use Turnstile.Schema

  object_type :document
  carries [:program, :designating_office, :marking]
  # portions is not carried: the redacted read supplies a Portion decision (§2)
  ...
end
```

**Exemptions**. Two kinds, one struct: `%Turnstile.Exemption{on: schema | table, caller: module | :any, reason: String.t(), kind: :declared | :library}`.
- Per call: `turnstile: {:exempt, reason}` with a non-empty reason; recorded as `%Turnstile.Exemption{on: root source, caller: the calling module, kind: :declared}`.
- Library: `turnstile: {:exempt, :library}`, accepted only from `Turnstile.*` callers (the seam checks the caller module), set by library code for the ledger's events and counter tables, the projector checkpoint, genesis, and the owner-role repo.

Under the matching rule, `schema_migrations`, `oban_jobs`, and other framework tables declare no object type and pass; they need no exemption. Each exemption is recorded on the call's span with its reason.

**The owner-role repo**. Reconcile, genesis, the catalog check (§10), and test truncation run through the application's second Repo module, `use Turnstile.Repo, role: :owner`, named as `owner_repo` in the ledger tuple of `%Turnstile.Config{}` (§15). The `UnmediatedRepo` check accepts it, and the seam treats every call on it as library-exempt. Under Postgres it connects as the role that owns the tables, and the migrations give that role a `SELECT` policy on every protected table, so its reads are unfiltered while its writes still meet the write gates.

**Four extension points** for an adapter, all optional: `prepare_query/3`, which core defines and an adapter's rewrite runs inside; the write overrides; the raw wrap; and `around_query(query_or_changeset, decision, fun)`, which the seam calls for every mediated query and write, receiving the query or changeset, the decision in force, and a zero-arity function that runs the call. `turnstile_postgres` uses the fourth to open a transaction when none is open and to run `set_config/3` for the subject's session settings on every call (§4).

**The surface list and its proof**. The overrides and core's `prepare_query/3` are defined in a `@before_compile` hook with `defoverridable` and `super`, so they wrap whatever the application or adapter defined; an application's own tenancy `prepare_query` runs inside ours; overrides redeclare the default argument (`opts \\ []`) so every arity routes through them. The classification is a plain list in `Turnstile.Repo.Surface`, one entry per name and arity, the shorter arities default arguments generate included. Its proof is one Tier 1 test, `Turnstile.Conformance.RepoCase` (`use Turnstile.Conformance.RepoCase, repo: Example.Repo`), shipped so a thin app or an adopter runs it against its own Repo: it diffs the list against the Repo's exported functions, where an export outside the list fails with the function's name and arity and a Repo exporting a subset of the list passes (`read_only: true` drops the write bucket); then it calls each exported non-plumbing function with a fixture and no decision and asserts `Turnstile.Error.Unmediated`. Core pins `ecto` to the minor range the list was written against. ⟨verify⟩ hook ordering against the adapter's own `@before_compile` on the pinned Ecto: the same test asserts that `query/3` refuses without an exemption.

**Refusal**. Refusal raises `Turnstile.Error.Unmediated`, carrying the function, the root source, the decision's object type if any, and the caller. There is no mode that logs instead of raising.

**Fact recording.** A write to a fact schema records one fact event per changed fact field in the same transaction as the write (§8). For a single-row update or delete the seam re-reads the row under the dialect's lock clause inside its own transaction and takes `old` from the re-read, never from the changeset's `data`. The clause reaches core as the configured ledger's `lock` option, a string or `nil`, which a ledger that records through the seam declares in its options schema with the dialect's answer as the default; core spells no dialect. The seam sees every write that goes through the Repo, including `on_replace: :delete` and nested association writes; it cannot see a foreign key that cascades, so `turnstile_ledger` ships a catalog check that reads every foreign key with `ON DELETE CASCADE` or `SET NULL` into a fact schema and refuses when it finds one (§10).

**Proof at runtime.** `RepoCase` is the sweep. Explicit cases beside it: `preload`, `aggregate`, `exists?`, `stream`, `reload`, `insert_all` with entries and with a query source, an `Ecto.Multi` run through `transaction`, `query/3` without an exemption; and from the matching rules: a decision naming the wrong object type is refused, a preload without a decision is refused, a carried preload is allowed, a nested association write of another protected schema is refused; an `insert` with `on_conflict:` on a fact schema is refused; a `{:exempt, :library}` from a non-library caller is refused. ⟨verify⟩ that `prepare_query/3` fires for the queries `preload` generates on the pinned Ecto; the review of the pinned Ecto found it does, and the case settles it.

**Static checks**, shipped in core, advisory: `Turnstile.Credo.NoRawSQL` flags `Ecto.Adapters.SQL.query*` and `Postgrex.*` calls outside an allowlist (migrations, reconcile, the ledger's own code); `Turnstile.Credo.UnmediatedRepo` flags any `use Ecto.Repo` without `use Turnstile.Repo`, the owner-role repo excepted. Nothing else: a check that every Repo call carries options is the rejected compile-time heuristic reborn; module-dependency boundaries are `boundary`'s job, which core uses for its own top layer.

## §7 Audit records: shapes, span, caps, sizes, shape tests

**Shapes.**
- `authorize`, `check`: one record per object: subject, object type and id, operation, verdict, reason.
- `batch`, `filter`: one record for N objects with N verdicts; ids listed up to `caps[:batch_ids]`, beyond it a count and a SHA-256 of the sorted ids.
- `scope`: one record with the object type, the operation, and the enforced rule: the inspected `dynamic`, truncated at `caps[:rule_bytes]` with a hash of the full text, parameter lists longer than `caps[:batch_ids]` elided to a count and hash; plus ledger position and policy version. Under a denied precondition the rule is `dynamic([_], false)` and the verdict is `:deny`. The RLS variant: rule `true`, policy version the migration number, and `settings_hash`, a SHA-256 of the session settings in force, since those are what the database enforced.
- `review`: one record per review.
- Common fields (AU-3, AU-3(1)): type, time, source component, outcome, subject identity and kind (`:user | :non_person_entity | :privileged`), request or session id, adapter, policy version, `head_position` and `applied_position` (equal unless the adapter projects), `operation_id`. No attribute values by default.

**The head read**. In ledger mode Ecto every port call reads the counter row once, `SELECT position FROM turnstile_ledger_counter WHERE name = $1`; that is one query, counted explicitly below. In mode none there is no head and both positions are `nil`.

**Span.** `:start` is the decision, with its ledger position. `:stop` is rows returned, rows affected, `operation_id`, duration, and for bulk fact writes the minimum and maximum ledger positions. `:exception` is the failure. The position is stamped at decision time; the query runs in the same request; a `dynamic` built from prefetched subject attributes is as fresh as the decision, one built on subqueries is as fresh as execution; either gap is inside measured revocation latency; RLS evaluates at execution.

**Caps**: `caps[:batch_ids]` 1,000, `caps[:rule_bytes]` 4 KB, `caps[:policy_content_bytes]` 64 KB, one keyword field of `%Turnstile.Config{}` (§15); and `fact_insert_batch`, a dialect default (§11). Every decision is emitted; nothing is sampled.

**Sizes to plan against.**
- A decision record is 300 to 600 bytes. At `:all`, 1,000 port calls per second is about 86 million records a day, tens of gigabytes uncompressed: a log-pipeline sizing question for the adopter's SIEM, not for the library.
- A fact event row is 200 to 400 bytes; a million fact changes a year is a few hundred megabytes. Retention is the life of the system; partition by position range if growth demands it, since the read-from-position contract does not care.

**Shape tests**, in Tier 1, every pull request, cited by nothing. They assert counts (queries issued, from Ecto's `[:repo, :query]` telemetry with transaction-control statements filtered out; audit records emitted; ledger rows written) because every regression that matters changes a number: per-row inserts instead of batches, per-row telemetry, a forgotten no-op filter, `RETURNING` on a non-fact write, a per-row `check` inside `scope`. Counts are deterministic; timings measure the runner. Fixtures are small: the only size that proves anything is one more than a batch. Counts are stated per adapter and per ledger mode; the scoped `all` case:

| Case | Adapter | Ledger mode | Queries | Audit records | Ledger rows |
|---|---|---|---|---|---|
| scoped `all` over 1,000 rows | RBAC | Ecto | 2: head, query | 1 | 0 |
| | RBAC | none | 1: query | 1 | 0 |
| | Cerbos | Ecto | 2: head, query | 1 | 0 |
| | Cerbos | none | 1: query | 1 | 0 |
| | Postgres | Ecto | 4: `set_config`, head, query, clear | 1 | 0 |
| | Postgres | none | 3: `set_config`, query, clear | 1 | 0 |
| | OpenFGA | Ecto | 3: head, checkpoint, query | 1 | 0 |
| | OpenFGA | none | not run: the adapter requires a ledger | | |

The engine's own calls (Cerbos over its socket, OpenFGA's `ListObjects`) are not database queries and are counted by the adapter's client telemetry, one per port call. The remaining cases, under ledger mode Ecto unless stated:
- A mediated single-row fact write: the re-read, the write, one ledger insert, and the counter take (one statement, §9), no other query; and a ledger append that fails rolls the write back, the atomicity claim, tested by behaviour rather than by counting `begin`/`commit`.
- A bulk write touching no fact field, 1,000 rows: one query, no `RETURNING` in it, one audit record, zero fact events, no counter take.
- A `bulk_update` changing a fact field on 5,000 rows: one `UPDATE`, one counter take, three ledger `INSERT`s (the 2,000-row batch), one audit record, 5,000 fact events carrying the same `operation_id`.
- A `bulk_update` setting a fact field to its current value on 1,000 rows: zero fact events, one audit record, no counter take.
- The same single-row fact write in mode none: the write, no re-read, no ledger insert, one audit record.
- One tripwire, generously bounded, on the committed repo: the 5,000-row `bulk_update` completes in under ten seconds. It catches an order-of-magnitude mistake and nothing subtler.

**Numbers, not gates.** Real performance characterization is `mix turnstile.bench`, a Benchee suite run on demand (seam overhead per operation, bulk write throughput, scope compilation, the counter row's serialization cost) whose output is a committed table in the docs, refreshed when the seam changes, never a CI assertion. Revocation latency is a third thing: a measurement printed for comparison with the PS-4 value, taken end to end on the committed repo and reported, not bounded.

## §8 Bulk writes and fact fields

**The fact mapping macro**. A fact schema declares its mapping column by column with `use Turnstile.Schema`, the macro that also declares the object type and carried relations (§6). Per column: the kind, the subject column, the object column, and the element type for a set-valued column. Per row: what insert and delete mean, because a relationship row's existence is the grant and its other columns are attributes of that relationship. Only a change to a declared column is a fact.

```elixir
defmodule Example.Assignment do
  use Ecto.Schema
  use Turnstile.Schema

  object_type :assignment
  # the row is the grant: insert emits :relationship with new: :member | :lead,
  # delete emits :relationship with old: the role and new: nil,
  # a change to :role emits :relationship with attribute: :role, old, and new
  relationship subject: :user_id, object: :program_id, attributes: [:role]
  ...
end

defmodule Example.Marking do
  use Ecto.Schema
  use Turnstile.Schema

  object_type :marking
  fact :controls, kind: :object_attribute, object: :document_id, element: :control
  fact :list, kind: :relationship, subject: :element, object: :document_id, element: :user_id
  ...
end

defmodule Example.User do
  use Ecto.Schema
  use Turnstile.Schema

  fact :employment, kind: :subject_attribute, subject: :id
  fact :nationality, kind: :subject_attribute, subject: :id
  ...
end
```

A set-valued column emits one event per element added (`old: nil, new: element`) or removed (`old: element, new: nil`). A fact schema need not be protected: `Example.User` above declares facts and no object type, so its writes are recorded and pass the seam without a decision. The CUI mapping: Assignment and OfficeRole rows are relationships with a `role` attribute; `Marking.controls` and `Marking.list` are set-valued; `User.employment` and `User.nationality` are subject attributes; `Document.decontrol`, `Document.marking`, and `Portion.marking` are object attributes. The `turnstile_fga` tuple mapping (§13) reads these events, not the schemas.

**The event.** `%Turnstile.FactEvent{kind, subject_ref, object_ref, attribute, old, new, position, operation_id, at, by}`; `kind` is `:subject_attribute | :object_attribute | :relationship | :policy_version`; a ref is `{object_type, id}`; `position` is `nil` in mode none; `by` is the subject of the operation that wrote it.

- The events table is a transactional outbox: the fact event commits with the write it records, and the projector, replay, and reconcile read it afterwards from the same database, which is why every event carries `old` and `new` and why positions are gapless (§9).
- A single-row write emits one fact event per changed fact field. The seam takes `old` from a re-read of the row under the dialect's lock clause, inside the write's transaction, not from the changeset's `data`, which is whatever the caller loaded earlier. A bulk write whose `set` or `inc` touches no fact field emits none: one decision record, outcome count, no `RETURNING` requested.
- `insert`, `insert_all`, and `insert_or_update` with `on_conflict:` on a fact schema are refused with a pointer to the bulk API, because an upsert updates fact fields of existing rows with no changeset and no old value, and `RETURNING` cannot say which rows were inserted and which updated.
- Plain `update_all`, `delete_all`, `insert_all` against fact fields are refused by the seam when the configured ledger asks for it (the Ecto ledger does; mode none does not) with a pointer to `turnstile_ledger`'s `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, `bulk_insert/3`.
- `bulk_update` adds, per field it sets, a null-safe "is different" condition in plain Ecto: `is_nil(field) or field` differs from `^value` (a `not is_nil(field)` test when the value is nil). No fragment; portable. A row whose value already matches is not affected and emits nothing, so a million-row sync that changes nine facts records nine. Computed sets (`inc`, fragments) cannot be compared in advance and record every affected row, which is correct.
- The bulk API needs the affected rows back with their old values; the dialect answers how (§11): `RETURNING` where the database supports it (for an update, the old values come from a select under the lock clause first, in the same transaction; for a delete, the deleted rows), else select the rows first under the dialect's lock clause, then write.
- Fact events are inserted with `insert_all` in batches of `fact_insert_batch` inside the same transaction as the write, with positions taken from the counter row once for the whole operation (§9); each carries the `operation_id`, indexed.
- The audit record for the operation carries count, `operation_id`, and min/max position; an investigator pulls rows by `operation_id`. The example's chained store writes one chained record per operation.
- Smell: a job that flips a million authorization facts nightly is a modeling error; something bookkeeping-shaped has been declared a fact.

## §9 Ledger positions

Positions come from a counter row. The table is library-owned, created by `turnstile_ledger`'s migration helper:

```
turnstile_ledger_counter(name text primary key, position bigint not null)
```

with one row, `default`, at position 0, inserted by the same migration. Every fact-writing transaction takes its positions by this sequence:

1. Inside the writing transaction, lock the row named by `%Turnstile.Config{ledger_counter}` with the dialect's lock clause (`SELECT position FROM turnstile_ledger_counter WHERE name = $1 FOR UPDATE` on Postgres).
2. Count the events the operation will write, `n`.
3. Advance the row by `n`. `Turnstile.Ledger.Dialect.Postgres` does steps 1 and 3 in one statement, `UPDATE turnstile_ledger_counter SET position = position + $2 WHERE name = $1 RETURNING position`; another dialect may answer with the locked select and an update.
4. Insert the events with positions `previous + 1` through `previous + n`.
5. Commit.

Commit order is position order, there are no gaps, and the reader behind projection, reconcile, and replay is "from position N": `SELECT ... WHERE position > $1 ORDER BY position`. The head read is a plain select of the row (§7); the head is the row's committed value, every position at or below it is committed, and replay to the head is exact. A bulk write's positions are one contiguous range; its audit record names the `operation_id` as well as the range. The mechanism is the same on every database; the dialect seam stays so a Postgres watermark reader can be added later (§11).

The lock serializes fact-writing transactions. Tier 1 measures the cost on the committed repo: N concurrent fact-writing transactions on one counter row, with throughput and mean wait printed to the log as the serialization cost, never asserted. The interleaved-transactions case, also on the committed repo, opens two fact-writing transactions on one counter row and asserts that the second takes no position while the first is open, so commit order is position order and the reverse cannot arise, and that a reader from position N, once both have committed, sees every position above N once and skips none.

Naming the row is what keeps tests async. A sandboxed test holds its transaction for its whole life, so two async tests writing facts would contend on `default`. The test cluster's sandbox setup inserts a per-test row inside the sandbox transaction and points the config override at it (`Turnstile.Test.with_config(ledger_counter: "test-<id>", ...)`), so async fact-writing tests never contend, and positions taken inside a rolled-back sandbox transaction are rolled back with it; committed-repo tests use `default`.

## §10 Ledger modes: what each can claim

| Mode | Who owns the facts | What the library does | What the mode can claim |
|---|---|---|---|
| Ecto ledger | the application's tables | one fact event per changed fact field in the same transaction, through the seam, into a library-owned table; positions from the counter row; genesis; reconcile; the catalog check | no fact without an entry inside the application after genesis; drift from outside detected within the reconcile interval; replay exact to the head, and exact after reconcile for out-of-band drift |
| None | the application's tables | nothing | nothing about history: drift detection, point-in-time review, and account-management audit (AC-2(4)) are the application's to provide; decision events carry no position; an adapter that requires a ledger (OpenFGA) cannot be bound, and boot fails with `Turnstile.Error.Unsupported` |

A third mode, the application's own event store read through the fact mapping, is deferred; the ledger behaviour and the fact event's payload are its contract, so nothing in core changes when it returns.

Genesis: every current fact as an event at position zero, stamped "backfilled from tables on ⟨date⟩ by ⟨migration⟩", written through the owner-role repo; reconcile runs from there. Append-only: the dialect's migration grants the application role insert and never update or delete on the ledger table, and update on the counter table only. The catalog check runs at genesis and in the ledger's Tier 1 case: it reads every foreign key with `ON DELETE CASCADE` or `ON DELETE SET NULL` whose target is a fact schema (§11's cascade query) and refuses when it finds one. The example's migrations use no cascades into fact schemas. A conformance case for the ledger behaviour ships with core so an implementation over another store can prove itself.

## §11 The dialect

`Turnstile.Ledger.Dialect` is the behaviour behind the ledger's database-dependent mechanisms. `Turnstile.Ledger.Dialect.Postgres` is the one implementation, the reference, and the only one the suite runs; an adopter on another database implements the behaviour and proves it with the ledger's conformance case (§10). The seven callbacks, with the Postgres answer and what another implementation has to decide:

| Callback | `Postgres` | What another dialect answers |
|---|---|---|
| Rows back from a bulk write | `RETURNING` ids, deleted rows for deletes | whether the database can return rows; else select first under the lock clause, then write |
| `fact_insert_batch` | 2,000, against 65,535 bound parameters per statement | from its parameter limit per statement |
| Reader strategy | counter row; a watermark reader is a later option | counter row |
| Counter take | one `UPDATE ... RETURNING` | one statement where the database can, else the locked select and an update |
| Lock clause for select-then-write and the re-read | `FOR UPDATE` | its own spelling, or none where the database serializes writers |
| Append-only grant | `GRANT INSERT`, no `UPDATE`/`DELETE`, to the application role on the events table; `UPDATE` on the counter table | the same grants in its own syntax |
| Cascade query | `pg_constraint` (`confdeltype` in `c`, `n`) | `information_schema.referential_constraints` or its own catalog |

## §12 Toolchain pins and terms

**Toolchain pins**, verified 2026-09-07; S0 re-verifies and says where in its commit message.

| Component | Version | Nix expression | Where verified |
|---|---|---|---|
| nixpkgs | `nixos-unstable`, head `c043004d…` (2026-09-05) | the flake's locked input | stable 26.05 has openfga 1.14.2, so unstable is the branch matching every pin at once |
| Erlang/OTP | 29.0.6 | `beam.packages.erlang_29` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/erlang/29.nix, same on `nixos-unstable` |
| Elixir | 1.20.4 | `beam.packages.erlang_29.elixir_1_20` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/elixir/1.20.nix (minimum OTP 27, maximum 29) |
| PostgreSQL | 18.6 | `postgresql_18`, written explicitly, never the bare `postgresql` alias | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/18.nix; the alias is 18 on unstable and 17 on both stable branches (`pkgs/top-level/all-packages.nix`) |
| OpenFGA | 1.19.0 | `pkgs.openfga` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/op/openfga/package.nix; release https://api.github.com/repos/openfga/openfga/releases/latest (published 2026-08-25) |
| Cerbos | 0.55.0 | a `stdenvNoCC` derivation that `fetchurl`s `cerbos_0.55.0_<Linux\|Darwin>_<x86_64\|arm64>.tar.gz` per system with hashes in the flake | absent from nixpkgs on every branch: https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/ce/cerbos/package.nix (404), https://github.com/NixOS/nixpkgs/issues/290460; release https://api.github.com/repos/cerbos/cerbos/releases/latest (published 2026-08-13); asset pattern from the same response, tag has `v`, filename does not |
| services-flake | active, last commit 2026-08-18 | the flake's input; `postgres` service, Cerbos and OpenFGA as process-compose processes | https://github.com/juspay/services-flake; https://community.flake.parts/services-flake/services (no cerbos or openfga service) |
| Hex: nimble_options, mox, stream_data, boundary, styler, muontrap | 1.1.1, 1.3.1, 1.4.0, 0.10.4, 1.12.2, 2.0.0 | `mix.lock` | https://hex.pm/api/packages/<name>; muontrap 2.0.0 is a new major, check its changelog |

Nix is not installed on the development Mac; the S0 agent installs it and stops to ask before running the installer. No Docker.

Each thin app's README carries the translation table from the domain's words to the adapter's (Assignment to `member` tuple, marking to policy attribute, designator to `WITH CHECK` role); its CI job is `docs/testing.md` §7.

**Terms**, held here until the package glossaries exist; each moves to the glossary of the context that owns it.

| Term | Meaning | Owner |
|---|---|---|
| Reference monitor | The part of a system that checks every access; always invoked, tamperproof, small | core |
| Subject / object / operation / environment | Who is asking, about what, to do what, under what conditions | core |
| Attribute | A fact about a subject or object that a rule can test | core |
| RBAC / ABAC / ReBAC | Rules over roles / over any attribute / over relationships in a graph | core |
| PEP / PDP / PIP / PAP | Where a request is stopped / where the answer is computed / where attributes come from / where rules are written | core |
| Port / adapter | The interface in core / an implementation of it for one mechanism | core |
| Conformance suite | The tests any adapter must pass; the real contract | core |
| Deny by default / fail closed | No unless a rule says yes / no when the system cannot decide | core |
| Sidecar | A small server running beside the application (Cerbos) | `turnstile_cerbos` |
| `scope` / `dynamic` | Narrow a query to what the subject may see / the Ecto where-clause fragment it returns, which can only narrow | core |
| Scope fidelity | `scope` returns exactly the rows `check` would allow | core |
| Row-level security | Postgres policies applied to every query on a table; `USING` for reads, `WITH CHECK` for writes | `turnstile_postgres` |
| Write gate | A rule the database enforces on inserts and updates without application code; a printed note, not a rule | `turnstile_postgres` |
| Mediated Repo, the seam | A Repo that refuses calls carrying no decision and no exemption | core |
| Exemption | A named, logged opt-out from mediation, per call, with a reason | core |
| Protected schema / carried relation | A schema that declares an object type / an association the parent's decision covers | core |
| Event / ledger / fold / replay | An immutable record of a change / an append-only list of them / reducing them to state / folding up to a date | `turnstile_ledger` |
| Transactional outbox | A record committed in the same transaction as the write it describes and read afterwards by consumers from the same database; the ledger's shape, never emptied | `turnstile_ledger` |
| Fact event (four kinds) | Subject attribute; object attribute; relationship; policy version, each with old and new | core |
| Fact mapping | The declaration, column by column, from an application's schemas to the four kinds | core |
| Ledger position / head / applied position | The index in the ledger / the counter row's committed value / the position an adapter's state has applied | `turnstile_ledger` |
| Counter row | The locked row every fact-writing transaction takes positions from | `turnstile_ledger` |
| Genesis | The backfill that gives an existing application's ledger an origin | `turnstile_ledger` |
| Drift / reconcile | Facts changed outside the seam / checking the tables against the ledger on an interval | `turnstile_ledger` |
| Projection / projector / checkpoint | How an adapter's state relates to the ledger / the process that drains it / the position it has applied | core, `turnstile_fga` |
| Audit record | A log entry with the shape AU-3 requires | core |
| Telemetry | Elixir's convention for a library to publish events that handlers consume | core |
| SIEM | The security team's central log system; a sink | core |
| Hash chain / anchoring | Each record hashes the previous; keeping the head somewhere the attacker cannot write | `turnstile_example` |
| Continuous evaluation | Attributes looked up on every check, never cached across requests | core |
| Revocation latency | Time from a revoking change to the first denial; evidence, measured | core |
| Environment fact (port-supplied / caller-supplied) | Time from the clock behaviour / facts only the caller knows | core |
| Re-authentication | Prove it is still you before sensitive operations | `turnstile_example` |
| User / NPE / privileged user | A person / software acting alone / a person who can change the system; the subject's kind | core |
| Least privilege / separation of duties | The least access needed / dangerous combinations split between people | `turnstile_example` |
| Audited override (break-glass) | Privileged access past the rules, with justification, logging, and reporting | `turnstile_example` |
| CUI | Controlled unclassified information; protected by law, below classified | `turnstile_example` |
| Category (Basic / Specified) | What kind of information; Specified brings its own handling rules | `turnstile_example` |
| Dissemination control | Who may not receive it, below the default | `turnstile_example` |
| Marking / portion marking / banner / decontrol | Categories and controls / a marking per portion / the union of the portions' markings / the end of protection | `turnstile_example` |
| Designating agency / lawful government purpose | Who declared it CUI / the legal basis for access | `turnstile_example` |
| Redacted read | The document with the portions the subject may not read removed | `turnstile_example` |
| FISMA / FIPS 199 / 800-53 / 800-53B | The law / impact levels / the catalog / the baselines | `PLAN.md` |
| Control / enhancement / family | A requirement (AC-2) / an optional sharpening (AC-2(4)) / a group (AC) | core |
| ODP / FedRAMP-assigned parameter | A blank in a control / a blank FedRAMP fills | core |
| Baseline / beyond baseline | The subset required at an impact level / cited but not required | core |
| Dialect | The behaviour behind the ledger's database-dependent mechanisms (§11); Postgres ships | `turnstile_ledger` |
| The line | Opinionated below the port; above it the database is reached only through the ledger behaviour and `around_query/3`, checked at compile time | core |
| Assessment-ready | The plan's word; never "compliant", never "FedRAMP Ready" | `PLAN.md` |
| Declaration / scenario / capability | What an adapter or thin app states about itself / a cited test / a rule's level with the enforcing component | core, `turnstile_example` |
| Tier 1 / Tier 2 | Port guarantees over a neutral fixture / CUI scenarios per thin app | core, `turnstile_example` |
| `review` | Who can do what, today or on a date | core |
| Thin app | One of the four applications that bind the library app to an adapter | `turnstile_example` |

## §13 The OpenFGA adapter

The design note for `turnstile_fga`. It began as an exercise (does the plan's altitude hold if an adapter is a relationship graph) and became the decision: the port, the seam, and the events survive untouched, three of the CUI rules come out cleaner on a graph than anywhere else, and the costs are the kind of thing the evidence exists to show. The three core amendments the exercise found (`applied_position` beside `head_position`, `requires_ledger`, the projection behaviour's checkpoint and `rebuild/1`) are applied for every adapter and listed in `PLAN.md`'s decisions.

**Zanzibar in the plan's words.** A Zanzibar-style system stores tuples, `(user, relation, object)` such as `user:alice member program:9`, and an authorization model that says how relations compose: directly assigned, computed from other relations on the same object, or followed through a related object ("members of the document's program"). OpenFGA is the open-source implementation: a server with its own datastore, an API of `Check`, `BatchCheck`, `ListObjects`, `ListUsers`, `Expand`, `Read`, `Write`, and `ReadChanges`, models that are immutable and versioned by id, and conditions, small CEL expressions on tuples, evaluated against a context sent with each check.

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
| the adapter's working state | the FGA store, a projection of the ledger, fed by the projector |
| revocation latency | commit, projector drain, engine write, check-cache TTL |

The one structural difference from the other three adapters: their working state is the application's tables. FGA's is a copy, in another store, kept current by the projector. That is what `Turnstile.Projection` is for. The ledger is the assessment's system of record and the projector reads it; the ledger-as-outbox shape is accepted, since the drain by diff answers the duplicate-write question and reconcile gives the 3PAO the ledger-versus-engine comparison.

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
    define agency: [agency]
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
    define can_override: operator from designating_office

type portion
  relations
    define document: [document]
    define category: [category, category with before_decontrol]
    define listed: [user]
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

type proposal
  relations
    define office: [office]
    define proposer: [user]
    define can_approve: approver from office but not proposer

condition before_decontrol(decontrol_at: timestamp, current_time: timestamp) {
  current_time < decontrol_at
}
```

Rule by rule. C1 is `lawful_purpose`. C2 is `can_read: lawful_purpose but not blocked`: every flag present must be cleared, and an absent flag blocks nobody. C3: a Specified category carries its own wildcard flags, and `fedonly_applies from category` inherits them; nothing is copied. C4: the document's flags include `from portion`, so the banner is the union by construction on this adapter as well as at write time in the domain; the redacted read is `can_read_redacted` on the document and `can_read` per portion, whose `scope` is a `ListObjects` over `portion`. C5: a document with a decontrol writes its flag and category tuples with `before_decontrol` and the date; one without writes them plain; after the date the flags evaluate false and only C1 remains. C6: `listed` is a per-document grant and combines with nothing; the model has no path from `listed` to `lawful_purpose`. C7 is `can_change_marking`; the write itself is gated by the seam, not by FGA. C8, re-authentication, is not modeled: it is a fact about the session, and putting it in a condition would make every use of `designator` demand session context, so the adapter checks it from the environment before calling FGA, as the RBAC adapter does. C9 is `can_approve: approver from office but not proposer`. C10 is `can_override` plus the justification and the event, in code. C11 holds per check, up to the projector's lag. C12 is measured. C13 is `ListObjects`, by FGA's definition of it, under the cap. The per-rule levels are `example_fga`'s declaration (§3), not this package's.

**The tuple mapping** (`ExampleFga.TupleMapping`, implementing `Turnstile.Fga.TupleMapping`). It maps fact events (§8), with their `old` and `new`, to tuple writes and deletes. Attributes become reified entities, a country, an employment kind, because a graph compares by walking, not by equality.

| Fact event | Tuples (user · relation · object) |
|---|---|
| Assignment(U, P, member or lead), a relationship | `user:U · member \| lead · program:P`; a `role` change deletes the old relation's tuple and writes the new |
| OfficeRole(U, O, designator or approver), a relationship | `user:U · designator \| approver · office:O` |
| Program in Agency; Office in Agency | `agency:A · agency · program:P`; `agency:A · agency · office:O` |
| Document's program and designating office | `program:P · program · document:D`; `office:O · designating_office · document:D` |
| Portion under Document | `portion:X · portion · document:D`; `document:D · document · portion:X` |
| Document's or Portion's categories | `category:C · category · document:D` (or `portion:X`), with `before_decontrol{decontrol_at}` when set |
| Marking's controls, one event per element | `user:* · fedonly_applies · document:D` (and the others), with the condition when set; a removed element deletes its tuple |
| Marking's list, one event per element | `user:U · listed · document:D`, plus the `user:* · list_applies · document:D` flag while the list is non-empty |
| REL TO countries | `country:CC · releasable_to · document:D` |
| Specified category's implied controls | `user:* · fedonly_applies · category:C`, written once per category |
| User's employment; nationality | `user:U · member · employment:federal`; `user:U · member · country:CC`; a change deletes the old entity's tuple and writes the new |
| Agency's domestic country; federal marker | `country:CC · domestic · agency:A`; `employment:federal · federal · agency:A` |
| Privileged user | `user:U · operator · agency:A` |
| Proposal (C9) | `office:O · office · proposal:P`; `user:U · proposer · proposal:P` |
| Decontrol set or changed | a read-diff-write: the drain reads the object's flag and category tuples, computes the tuples the new parameter requires, and writes the difference, never the object's tuples whole. A tuple is identified by its user, its relation, and its object, and a condition is a value carried on it rather than part of that identity, so a changed date is the same tuple with another context: the drain deletes that tuple and writes it again, in two calls, because one `Write` refuses a tuple key that appears in both its deletes and its writes (OpenFGA 1.19.0) |
| Policy version | write the model; record the model id and the DSL text (small) in the policy-version event |

**The client behaviour and its fake**. `Turnstile.Fga.Client` is the only path to the server: `create_store/2`, `write_model/3`, `check/3`, `batch_check/3`, `list_objects/3`, `expand/3`, `read/3`, `write/3`, each returning `{:ok, t} | {:error, %Turnstile.Error.Engine{}}` and never raising. `Turnstile.Fga.Client.Fake`, in test support, is an `Agent` per test holding stores, models, and tuples; its `write/3` rejects a duplicate write and a missing delete as the server does, atomically per call; its `read/3` pages by object type; its `check/3` and `list_objects/3` answer from directly present tuples without evaluating the model, returning values of the real type. The projector's convergence and drift cases run against the fake first, without a server; the decision cases run against `openfga run --datastore-engine memory` with a store per test.

**The projector.** `Turnstile.Fga.Projector` implements `Turnstile.Projection` (`checkpoint/1`, `drain_once/1`, `rebuild/1`, `reconcile/1`): it reads fact events from the ledger's reader (§9) from its checkpoint, applies the tuple mapping, writes in batches (default `maxTuplesPerWrite` 100 on the pinned server, counting the deletes and the writes of one call together), and advances the checkpoint in the application's database.
- **Checkpoint per acknowledged write**. The checkpoint advances after every acknowledged `Write` call, to the position of the last event that call covered, so a crash between batches leaves `applied_position` exact. A step whose difference asks for a tuple to be deleted and written again takes two calls, and the checkpoint advances after the second of them, since the state between the two is neither the old one nor the new one.
- **Drain by diff**. For each object a batch touches, the drain computes the difference between the tuples the fold requires and what `Read` returns for that object, and writes only that difference. It tolerates no errors: a rejected `Write` fails the drain, which re-runs from the checkpoint. A re-drain after a crash therefore converges (a Tier 1 case).
- **Rebuild into a fresh store**. `rebuild/1` takes the projector's configuration, creates a store, publishes the pinned model, folds from position zero into it, and returns `{:ok, store_ref}`; serving continues from the old store until the application swaps `store_id`, a dated configuration change. Minutes for a million facts, beside the serving store.
- **Reconcile compares the fold to `Read`.** `Read` pages tuples by object type; drift is a tuple present in one and not the other. Cost is proportional to tuples, so the interval is longer than the Ecto ledger's table comparison.
- **A long-lived process.** The drain interval belongs to the projector process, which the thin app starts beside the reconcile scheduler; tests never start it and drive `drain_once/1` instead.

The adapter therefore requires a ledger and declares so; in ledger mode none there is nothing to drain, and boot fails with `Turnstile.Error.Unsupported` rather than pretend dual writes are a projection.

**Decisions, scope, replay.** `Check` with the model id pinned per request and `consistency` set per operation: `HIGHER_CONSISTENCY` for anything under C7 to C10, `MINIMIZE_LATENCY` allowed for reads, a constant of the adapter. The decision event carries the model id as its policy version, the ledger head at decision time, and the checkpoint as `applied_position`; replay uses the applied position, because that is the state the engine saw. `ListObjects` returns ids, so `scope` is `dynamic([d], d.id in ^ids)`, and the `caps[:batch_ids]` elision applies to the recorded rule; above the cap the seam falls back to `filter` per page with `BatchCheck`; tenant-scoping the query first (`d.agency_id == ^agency`) keeps most lists under the cap. Replay: fold the ledger to *t*, write the tuples into a throwaway OpenFGA with the in-memory datastore, pin the model in force at *t*, and `Check`; heavier than Cerbos's replay because the state must be loaded, lighter than Postgres's because no schema is involved. Revocation latency decomposes as commit, drain, engine write, check-cache TTL if the cache is enabled, and the consistency mode; the committed-repo case measures it (§4).

**Declaration summary**, domain-free: `requires_ledger: true`; `scope_cap` the `ListObjects` cap. Constants: consistency per operation and the `ListObjects` cap; option: the drain interval (§15).

**Projection cases in Tier 1**, each `@tag :committed`, driving `drain_once/1`: measured lag, from a fact's commit to the checkpoint advance that covers it; drift from a tuple deleted through the client directly, caught by reconcile; a re-drain after a simulated crash (a `Write` acknowledged, the checkpoint advance interrupted) converges. They activate only for an adapter that declares a projection.

## §14 Test environment, conformance artifacts, conformance mechanisms

See `docs/testing.md`: a Nix flake pins the toolchain (§12) and provides Postgres, Cerbos, and OpenFGA binaries; `mix test` starts an ephemeral cluster per run, two roles (`turnstile_owner` owns the tables and runs migrations; `turnstile_app` does not own them and carries `NOBYPASSRLS`, §4), a sandboxed and a committed database, and three test repos, of which `Turnstile.TestRepos.Owner` is an owner-role repo in §6's sense; every test owns its state so `async: true` is the default; `:committed` and `:tripwire` are the tagged exceptions; shape tests run on every pull request and benchmarks on demand. The committed-repo list: the interleaved-transactions and lock-cost cases (§9), the append-only grant, reconcile against out-of-band writes, truncation through the owner-role repo, the three projection cases (§13), and the revocation-latency case per adapter (§4).

**The neutral fixture and `priv/conformance/`**. Tier 1's fixture is core's: two object types, two roles, one attribute, one relationship, as Ecto schemas against the same Postgres the rest of the suite uses. Each adapter package ships what that fixture needs on its mechanism under `priv/conformance/`: `turnstile_postgres` the RLS migration for the fixture tables; `turnstile_cerbos` the policies; `turnstile_fga` the model and a tuple mapping module; `turnstile_rbac` the role table and predicates. `AdapterCase` (`use Turnstile.Conformance.AdapterCase, adapter: Turnstile.Code`) passes the adapter through the config override, so all four run in one `mix test` as async modules.

**Conformance mechanisms**, two modules that the scenarios and Tier 1 rest on.

| Module | What it is | Package |
|---|---|---|
| `Turnstile.Conformance.Case` | The `scenario` macro as a `test` tagged with its rule, its controls, and the capability the declaration records, an `unsupported` scenario skipped with the declaration's note as the reason; the count test that `use Example.Scenarios` defines last (`docs/testing.md` §6); the assertions as macros so a failure points at the scenario | `turnstile_core` |
| `Turnstile.Conformance.AdapterCase` | The adapter case template: the port's invariants as `stream_data` properties over generators the adapter's test module supplies; scope fidelity, deny by default, record-then-erase, batch agreement, fold-then-replay | `turnstile_core` |

**Declared-fact coverage**, one Tier 1 case per adapter whose rules read columns: every column an adapter's rules read is a declared fact (§8). For `turnstile_rbac` and `turnstile_cerbos` the case walks the `dynamic` that `scope` returns, subqueries included, and collects every field reference against the schema it belongs to; for `turnstile_postgres` it reads the policy predicates from `pg_policy` and collects the column references. A column counts as declared when a `fact` or `relationship` declaration on its schema names it, as the fact column, the subject column, or the object column; the primary key and the foreign key of a carried relation are references to the object and count as declared. A rule that reads an undeclared column fails the case with the column's name, because a decision that depended on it would replay from a ledger that never recorded it.

**Schema dump**. Each thin-app CI job dumps `pg_dump --schema-only` after migrations into `priv/schema/<adapter>.sql` and fails on a diff against the committed file; the Postgres one is the teaching artifact.

## §15 The configuration struct

`%Turnstile.Config{}` is validated once at boot from a `NimbleOptions` schema and is the only runtime configuration the library reads. The schema is frozen at S1. Tests override any field through `Turnstile.Test.with_config(overrides, fun)`, which puts the override in the process dictionary; the seam's resolver checks `self()` and then the `$callers` chain.

| Field | Type | Default |
|---|---|---|
| `adapter` | `module \| {module, keyword}`, the module implementing `Turnstile.Adapter` and its options, validated by the adapter's own schema; a bare module means `[]` | required |
| `ledger` | `{Turnstile.Ledger.Ecto, repo: module, owner_repo: module} \| :none`; `owner_repo` is `use Turnstile.Repo, role: :owner` | required |
| `ledger_counter` | `String.t()`, the counter row's name; a test override that the sandbox sets per test, left at the default by applications | `"default"` |
| `clock` | module implementing `Turnstile.Clock` | `Turnstile.Clock.System` |
| `caps` | keyword: `batch_ids` (ids listed in a record), `rule_bytes` (rule text kept in a record), `policy_content_bytes` (policy text kept by value) | `[batch_ids: 1_000, rule_bytes: 4_096, policy_content_bytes: 65_536]` |

Adapter options by adapter: `turnstile_cerbos` `address`; `turnstile_fga` `endpoint`, `store_id`, `model_id`, `drain_interval`, `client` (the behaviour's implementation, the fake in tests); `turnstile_rbac` and `turnstile_postgres` none, so their entry is the bare module. Consistency per operation and the `ListObjects` cap are constants of `turnstile_fga`.
