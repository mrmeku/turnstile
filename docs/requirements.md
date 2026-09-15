# Requirements

*The requirement lines that reach this library, where each comes from, and what answers it. One row per applicable line. Maintained by a person; no code reads it.*

## 1. Source

NIST SP 800-53 Rev 5, as the FedRAMP Rev 5 Moderate baseline selects and parameterizes it. The selections and parameter values below were read on 2026-09-14 from the OSCAL profile `FedRAMP_rev5_MODERATE-baseline_profile.json`, in the oscal-compass-lab mirror of GSA's fedramp-automation repository, and the control text from the csf.tools mirror of the Rev 5 catalog. FedRAMP 20x key security indicators are a cross-reference and not a source.

**Selected in the Moderate baseline**, of the controls this repository cites: AC-2, AC-2(1), AC-2(2), AC-2(3), AC-2(4), AC-2(5), AC-2(7), AC-2(9), AC-2(12), AC-2(13), AC-3, AC-5, AC-6, AC-6(1), AC-6(2), AC-6(5), AC-6(7), AC-6(9), AC-6(10), AU-2, AU-3, AU-3(1), AU-6, AU-6(1), AU-6(3), AU-9, AU-9(4), AU-11, AU-12, CM-3, CM-3(2), CM-3(4), CM-5, CM-5(1), CM-5(5), IA-11, PS-4, PS-5.

**In no baseline**, and cited by nothing here: AC-3(7), AC-3(8), AC-16, AC-25. No control in the baseline asks for a reference monitor, and this library does not claim one.

**Parameters that bind the library.**

| Parameter | Value | What it means here |
|---|---|---|
| AU-2 `au-02_odp.01` | ends "For Web applications: all administrator activity, authentication checks, authorization checks, data deletions, data access, data changes, and permission changes" | authorization checks are the decision event; data access is the access event; data changes, deletions, and permission changes are the change event; administrator activity is a decision or change whose subject kind is `:privileged`; authentication checks are the application's, outside the library |
| AU-3(1) `au-03.01_odp` | includes "characteristics that describe or identify the object or resource being acted upon" | every event carries the object type and the ids it acted on |
| AC-2(4) | "Automatically audit account creation, modification, enabling, disabling, and removal actions" | a single-row write to a schema audited as `:user` emits one change event |
| AC-6(9) | "Log the execution of privileged functions" | every decision for a `:privileged` subject is evented with that kind |

## 2. The table

A law is a Tier 1 conformance test in `Turnstile.Conformance.AdapterCase`, run by every adapter against its real engine; `docs/conformance.md` carries the frozen list. A guarantee `E1` to `E5` is asserted by `Turnstile.Conformance.RepoCase` against a repo. A scenario id names a row of the example's table in `docs/example.md`, which shows a domain rule and asserts nothing neutral. The vocabulary of a law is the neutral fixture's: subject `{kind, id}`, object `{type, id}`, operation, grant (a membership row), fact (clearance, role, expiry, kind), decision, event.

| Control | Answered by | What is asserted |
|---|---|---|
| AC-2, AC-2(4) | `ac2-01` | A single-row insert, update, or delete of an account through the seam emits one change event naming the deciding subject, the target `{:user, id}`, and the clearance before and after. |
| AC-2(2), AC-2(3) | `ac2-02` | A grant that expires one second after the port's clock allows and one that expired one second before denies, by the configured clock and not the database's. |
| AC-2(3), PS-5 | `ac2-03` | A subject whose account no longer satisfies the rule is denied at the next check with no other change. |
| AC-2(7), AC-6(7) | `ac2-04` | Review returns, for every subject including a privileged one, a rule that lists exactly the objects check allows, with one decision per subject and one for the reviewer under one operation id. |
| AC-2(13), PS-4 | `ac2-05` | After a grant is revoked the next check denies; the latency from revocation to denial is printed and never asserted. |
| AC-3 | `ac3-01` | check agrees with the world's own rule for every subject, operation, and object drawn. |
| AC-3 | `ac3-02` | An ungranted object, an unknown operation, an unknown subject, and an unknown subject kind are denied, the last before the adapter is called. |
| AC-3 | `ac3-03` | scope returns exactly the rows check allows, for the scoped schema and for the schema its decision carries. |
| AC-3 | `ac3-04` | scope over a thousand rows is one decision and one query beyond setup. |
| AC-3 | `ac3-05` | An unreachable decider denies and emits one decision event carrying the exception. |
| AC-6(2) | `ac6-01` | A user holding a grant is allowed, and the privileged subject of the same account is denied the same object. |
| AC-6(9) | `au2-01` for kind `:privileged` | Every decision for a privileged subject is evented with `subject_kind: :privileged`. |
| AU-2 | `au2-01` | Every authorize and check emits exactly one decision event carrying subject, kind, operation, object, verdict, reason, version, operation id, and time. |
| AU-2 | `au2-02` | A denial's decision event carries the reason for it. |
| AU-2 | `au2-03` | scope and review emit decisions whose verdict is scoped. |
| AU-3 | `au3-01` | No value in a decision event equals an attribute value of the world. |
| AU-3 | `au3-02` | A change event carries operation, kind, target, actor, time, operation id, and the old and new value of every fact column that changed. |
| AU-3 | `au3-03` | An access event carries object type, ids, decision id, subject, operation id, and time. |
| AU-3(1) | `au3-04` | Within one operation id the decision, change, and access events each carry it. |
| AU-12, AC-2(4) | `au12-01`, E1 | A single-row write to an audited schema emits its change event inside the write's transaction. |
| AU-12 | `au12-02`, E2 | A bulk write to an audited schema raises and changes nothing. |
| AU-12 | `au12-03`, E3 | A write that goes around the seam emits nothing. |
| AU-12 | `au12-04` | A write the database refuses leaves no row and no event. |
| AU-12 | `au12-05` | An unmediated read or write of a protected schema is refused. |
| AU-12 | `au12-06`, E5 | Every mediated read of a protected schema emits one access event. |
| AU-12 | `au12-07`, per adapter | Every column a rule reads is a declared fact, so a permission-relevant change is a change event; one coverage test per adapter whose rules read columns, and the tuple mapping for OpenFGA. |
| CM-3, CM-5 | `cm3-01` | Publishing a version emits the adapter's version event naming the author and the approval. |
| CM-3(2) | `cm3-02` | A decision reports the version it was taken under, before and after a new version is published. |
| CM-5(1) | `cm3-03` | A tightened rule is a policy version whose event names the artifact it is on this adapter. |
| CM-3(2) | `cm3-04` | After a rule is tightened the reader it excludes is denied; the propagation latency is printed and never asserted. |
| AC-5 | `sod-01` to `sod-03` | Separation of duties in the example: the approver of a marking is not its proposer. |
| AC-6, AC-6(1), AC-6(5), AC-6(10) | `lp-01` to `lp-08` | Least privilege in the example: lawful purpose, controls, the designator role, and what a review reports. |
| IA-11 | `ia-01` to `ia-03` | Re-authentication in the example: a marking change within the window, outside it, and with no window given. |
| AC-6(9), AU-6 | `ovr-01` to `ovr-03` | The audited override in the example: privileged subject, justification, its own event, and its report. |
| E4 | `RepoCase` | A consumer that writes to the same repository from its handler joins the write transaction. |

**What the library does not guarantee.** That a record is stored, that a handler keeps running, that the write committed, or that the old value in a change event was current at the moment of the write; the old value is the row the caller loaded.

## 3. The consumer's lines

The library emits what these need. The deployer's system, the consumer that attaches to the events, satisfies them.

| Control | What the consumer does |
|---|---|
| AC-2(1), AC-2(5), AC-2(9), AC-2(12) | Automates account management, logs out inactive sessions, manages shared accounts, and monitors for atypical use, over the change and decision events |
| AU-6, AU-6(1), AU-6(3) | Reviews the records weekly and correlates across repositories |
| AU-9, AU-9(4) | Protects the records and restricts access to them |
| AU-11 | Retains the records for the period M-21-31 sets |
| CM-3(4), CM-5(5) | Puts a security representative on the change board and limits who may publish a version |
| AU-5 | Alerts on a handler failure, which telemetry reports as its own event |

## 4. How a row is kept honest

A row is complete when its control line has a law, a guarantee, an example scenario, or a stated consumer responsibility, and every law id here exists in `Turnstile.Conformance.Law.all/0`, which the freeze test holds to `docs/conformance.md`. A control number is checked against the catalog before this file is published. A row that cites a control outside the baseline is a review failure.
