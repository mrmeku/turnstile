# The example

*The CUI domain the four thin applications share, its thirteen rules, and the scenario table every binding runs. This is the how-to: it shows how an application expresses its needs through the port under each adapter. What it asserts about the port itself is in `docs/conformance.md`.*

## 1. The domain

Controlled unclassified information, CUI, is information protected by law below the classified level. A document carries a marking: the categories that say what it is, and the dissemination controls that say who may not receive it. An agency designates it through one of its offices, a program gives its members a lawful purpose to read it, and a designator in the designating office is who may change its marking.

| Term | Meaning |
|---|---|
| Document | The protected record: a title, a designating office, a program, a decontrol date, a marking, portions, and proposals |
| Portion | One part of a document with a marking of its own; the redacted read returns the portions the subject may read |
| Marking | The categories, controls, and releasable-to list a portion carries and a document's banner combines |
| Banner | A document's marking: the one that admits no subject a portion of it denies, kept at write time (C4) |
| Control | One dissemination control: `federal_only`, `no_foreign`, `named_list`, or `releasable_to`, each a test on the subject (C2) |
| Category | A CUI category; a specified category implies controls that count as declared (C3) |
| Decontrol | The date after which C2 to C4 no longer apply to a document; C1 still does (C5) |
| Named list | The users a marking names directly; membership grants nothing beyond C1 (C6) |
| Program | The unit an assignment belongs to; an open program gives lawful purpose to its members (C1) |
| Assignment | A user's role in a program: `member` or `lead` |
| Office role | A user's role in an office: `designator` or `approver` (C7, C9) |
| Designating office / agency | The office that designated a document and receives its override reports / the agency it belongs to |
| Proposal | A marking change one designator proposed and a different approver approves (C9) |
| Override | A privileged read outside C1, with a justification, its own event, and a report (C10) |
| Privileged account | An account of kind `:privileged`, separate from the person's user account, that may hold the override permission |
| Re-authentication / window | The `reauthenticated_at` fact the identity layer supplies / how recent it must be for a C7 operation (C8), the organization's IA-11 parameter |
| Redacted read | The document with the portions the subject may not read removed |
| SIEM | The consumer of the library's three events: one OCSF record per decision, change, and access, held in memory |
| Access review | The report of who may do what on each agency's documents and of every privileged account |
| Fixture | The world every scenario starts from: two agencies, offices, programs, categories, and one account per role |
| Scenario | One row of §4, defined in a thin application's test module by `use Example.Scenarios` |
| Thin application | One of `example_rbac`, `example_postgres`, `example_cerbos`, `example_fga`: the binding of this domain to one adapter |

## 2. Dissemination controls and the portion

A category says what the information is; a control says who may not receive it, below the default that anyone with a lawful government purpose may. The Registry allows a fixed set; a document may carry several; all must hold. Four modeled, one per shape of subject test; FEDCON, NOCON, DISPLAY ONLY, and the attorney markings are the same shapes with other values.

| Control | Registry marking | Test on the subject |
|---|---|---|
| `federal_only` | FED ONLY | employment is federal |
| `no_foreign` | NOFORN | nationality matches the designating agency's |
| `named_list` | DL ONLY | the subject is on the marking's list, a per-object grant |
| `releasable_to` | REL TO | nationality is in the marking's country list |

**The portion**. `Portion(document_id, marking: Marking)` is a row under `Document`; a document may have none. The document's marking is its banner, the marking under which every one of its portions may be read (rule C4, enforced at write time in the domain). `Portion` declares its own object type, is not a carried relation of `Document`, and its `marking` is a fact field of kind `:object_attribute`.

Two read operations on a document. `read` is the whole document under the banner: a Document decision under C1 and C2 over the banner. `read_redacted` returns the document with the portions the subject may not read removed: a Document decision under C1 (`authorize(subject, :read_redacted, document)`), then a Portion `scope` (`scope(subject, :read, Portion)`) whose `dynamic` the seam applies to the portions query, `Repo.preload(document, :portions, turnstile: portion_decision)`. Because `Portion` is not carried, a preload without its own decision is refused (`docs/design.md` §4). Scope fidelity (C13) holds at portion level: the portions returned are exactly those for which `check(subject, :read, portion)` is true. Each adapter filters portions as rows of their own under a policy of their own:

| Adapter | Portion mechanism |
|---|---|
| `turnstile_rbac` | a `read` operation on `Portion` whose predicates are the document predicates over the portion's marking |
| `turnstile_postgres` | a second row-level security policy on the `portions` table; the `documents` policy is not consulted for portion rows |
| `turnstile_cerbos` | a `portion` resource kind with its own policy; `scope` over portions with derived markings is answered per portion |
| `turnstile_fga` | a `portion` type with a `document` parent, the control flags on the portion, and `can_read: lawful_purpose from document but not blocked` |


## 3. The rules

The thirteen rules of the example's domain, as a person wrote them. §1 defines the words they use.

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

**What enforces each rule.** Each thin application's README carries a table of the rules against what enforces each of them under that binding: the engine, the seam, the adapter, or the application's own code. That table is prose a person writes and keeps, and no code reads it. What a test carries instead is its tags. The `scenario` macro tags each test with its scenario id, the rule it tests, and the controls §4 cites for that id, so a control id is written once, in §4, and the tags are what a run reports from.

**Where the adapters differ.** Write gates without application code: Postgres only, where a C7-violating marking change is refused by the database whether or not the application asked. That is a property of Postgres rather than a rule, and no scenario tests it. Rules owned by non-developers, versioned and tested as their own artifact: Cerbos only. What an answer names: Cerbos names the policy it matched, code names the clause, OpenFGA names the relation, and Postgres names the policy of the operation, because the database does not report which policy admitted a row. Derived markings, which are C3 and C4 through portions: Cerbos plans over the attributes it is sent alone, so the derivation lives in the subquery a declaration names rather than in the policy, and nothing is materialized; OpenFGA walks them as tuple-to-userset, also with nothing copied. Request-time facts, which are C5 and C8: every adapter answers them, Postgres threads them through session settings, and OpenFGA takes C5 as a tuple condition with the moment in the check context and C8 in the adapter, from the environment, before the call. OpenFGA alone: C9 is `approver from office but not proposer`, and `scope` is `ListObjects` under a cap. The model and the tuple mapping are in the `example_fga` README.


## 4. The scenarios

Frozen: the freeze test in `example` reads this table and holds `Example.Scenarios.Table` to it row for row. Every row is a test in `Example.Scenarios` whose name is the sentence, written with the `scenario` macro (`scenario "enf-01", "<sentence>", rule: :c1 do ... end`), and run by each of the four thin applications. "Tests" names the C-rule, or `review` for the scenario that shows the port's review verb. Beyond-baseline citations are marked with an asterisk. What the laws of `docs/conformance.md` assert for every adapter is not repeated here: no scenario tests the events, the seam, or a policy version.

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
| `enf-17` | A Document of another Agency is neither returned by `scope` nor readable by `check` | enforcement | AC-3 | C1, C13 |
| `enf-18` | A User one Portion releases to and another does not is denied the whole Document | enforcement | AC-3, AC-16* | C4, C2 |
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
| `rev-06` | A revocation deletes nothing but the fact: the Document and the Program remain, and the grant and the revoke are both evented | revocation and expiry | AC-2(4) | C11 |
| `rvw-01` | The access review lists who can read what today, per Agency | access review | AC-2, AC-6(7) | `review` |
| `ia-01` | A designator whose session re-authenticated within the window changes a marking | re-authentication | IA-11 | C8 |
| `ia-02` | A designator whose session is older than the window is refused until re-authentication | re-authentication | IA-11 | C8 |
| `ia-03` | A marking change with no re-authentication fact supplied is denied | re-authentication | IA-11 | C8 |
| `ovr-01` | A privileged user with the override permission reads outside C1 with a justification, and the read emits its own event and is reported to the designating Office | emergency override | AC-6(9), AU-6 | C10 |
| `ovr-02` | Without a justification the override is denied | emergency override | AC-6(9) | C10 |
| `ovr-03` | The override never reaches C7: a privileged user cannot change a marking through it | emergency override | AC-6(9), AC-6(1) | C10, C7 |

No scenario tests "write gates without application code"; it is not a rule.

## 5. What each binding says

Each thin application's README carries what its binding costs, as the directory's contents explained in order, the table of what each rule is enforced by under that binding, and the translation table from this domain's words to the adapter's. Those tables are prose a person keeps, and no code reads them.
