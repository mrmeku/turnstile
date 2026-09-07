# Turnstile — proposed changes for plan v6
*Mode: Explanation.* Sections are written to be pasted into the plan or replace their v5 counterparts. Items marked ⟨verify⟩ need checking against the Rev 5 Moderate baseline profile or the 20x machine-readable docs; the lint should do that check permanently.

## 1. Vocabulary: what the plan says → what FedRAMP says

| Plan says | Say instead | Why |
|---|---|---|
| the federal control catalog | NIST SP 800-53 Rev. 5 ("Rev 5") | the name on every SSP, SAR, and KSI |
| the standard's attribute-based access-control guide | NIST SP 800-162 | |
| the contractor profile · the Cybersecurity Framework | NIST SP 800-171 · NIST CSF 2.0 | |
| the CUI regulation · the CUI Registry | 32 CFR Part 2002 · the NARA CUI Registry | |
| assessor | 3PAO (Third Party Assessment Organization) | the word on every Security Assessment Report |
| implementation statement | control implementation statement, with an **implementation status** — Implemented, Partially Implemented, Planned, Alternative Implementation, Not Applicable — in the System Security Plan (SSP) | the generator prints the status field, not only prose |
| gaps, "with what would close it" | POA&M items (Plan of Action and Milestones) | the template has fixed columns: weakness, detection source, remediation plan, scheduled completion, milestones, status; emit rows in that shape |
| settings a requirement leaves open | organization-defined parameters (ODPs); the ones FedRAMP fixes are FedRAMP-assigned parameters | |
| implemented by the service · configured by the customer · provided by the customer · shared · inherited | the SSP's origination values verbatim: Service Provider Corporate · Service Provider System Specific · Service Provider Hybrid · Configured by Customer · Provided by Customer · Shared · Inherited from pre-existing authorization | "implemented by the service" is not a value on the form |
| library implements · application must · organization must | the **responsibility split**; it is the input to the Customer Responsibility Matrix (CRM) | a different axis from origination — see §2 |
| the FedRAMP boundary · the boundary | authorization boundary | |
| a user, a non-person process, the platform operator | user · non-person entity (NPE) · privileged user | AC-2(7), AC-6(2), (9), (10) use these words |
| point-in-time review | account review (AC-2) and privilege review (AC-6(7)), with history | "access review" is what a 3PAO asks for by name |
| decision events · ledger events | keep as library terms; the statement calls them audit records (AU-3) | |
| component entry | inventory item, in the Integrated Inventory Workbook | |
| continuous-monitoring evidence | ConMon deliverable (Rev 5) · Ongoing Authorization Report (20x) | |
| assessment-ready | keep; avoid the exact phrase "FedRAMP Ready", which was a formal designation | |
| the regime | FedRAMP, with two tracks: Rev 5 and 20x | |

The assessment glossary (owned by `turnstile_assess`) grows to: control, enhancement, parameter (ODP), implementation status, origination, baseline, profile, SSP, SAR, POA&M, CRM, 3PAO, authorization boundary, inventory, ConMon, Key Security Indicator (KSI), Ongoing Authorization Report.

## 2. Two axes the plan fuses

- **Responsibility split** — who builds it: library, application, organization. This is what the library knows.
- **Control origination** — who is accountable on the SSP: the seven values in §1. This is what the provider declares; the library can only default it.

The generator carries both. Origination is a field in the application's declaration, defaulted per adapter and overridable; the example's defaults: programs, lists, and designators an agency sets → Configured by Customer; CUI training → Service Provider Corporate; everything the library or application implements → Service Provider System Specific. The responsibility split becomes the CRM rows.

## 3. Requirement groups → control ids

Keep the groups; cite ids now so the lint and the agent have a target. Extend the lint to check baseline membership against the FedRAMP Rev 5 Moderate profile (OSCAL, fedramp-automation repo) and to mark beyond-baseline citations. ⟨verify enhancement membership⟩

| Group | Primary | Also | Beyond baseline (cite, marked) | 20x family |
|---|---|---|---|---|
| Enforcement | AC-3 | | AC-25 (always invoked) · AC-3(7) RBAC | KSI-IAM |
| Least privilege | AC-6, (1), (2), (5), (9), (10) | AC-2(7) | | KSI-IAM |
| Separation of duties | AC-5 | | | KSI-IAM |
| Revocation | AC-2, PS-4, PS-5 | AC-2(1) | AC-3(8) revocation of authorizations | KSI-IAM |
| Decision audit | AU-2, AU-3, AU-3(1), AU-12, AC-2(4) | AU-9, AU-9(4), AU-11 | | KSI-MLA |
| Access review | AC-2 (account review), AC-6(7) | | | KSI-IAM |
| Re-authentication | IA-11 | | | KSI-IAM |
| Emergency override | AC-6(9), AC-2(2) | AU-6 | | KSI-IAM · KSI-MLA |
| Time-bounded access | AC-2(2), AC-2(3) | | AC-16 (the markings are security attributes) | KSI-IAM |
| Change control on policy | CM-3, CM-5 | | | KSI-CMT |
| Inventory | CM-8 | | | KSI-PIY |

Notes.
- AU-2: the FedRAMP-assigned parameter names, for web applications, authorization checks, data access, data changes, and permission changes among the events to log. ⟨verify Rev 5 wording⟩ "Every call is evented" is that parameter, met; the statement should cite it.
- Time-bounded access is thin on baseline citations; consider folding decontrol into Revocation as "an object attribute that changes on a date," keeping AC-16 as the beyond-baseline note.
- Change control is new: for rules in code and RLS, a policy version is a commit and a deploy, so CM-3 review is the approval — a strength for the 3PAO, and it should be a scenario.
- Tenant isolation: the example's Agency is the tenant. Say "tenant" in the model; SSPs answer the multi-tenant separation question under AC-3 and SC-4/SC-7, and the scenario for C13 is where it is proven.

## 4. Two tracks, one source of truth

FedRAMP now has two paths to a Moderate authorization: Rev 5 (SSP with control implementation statements, OSCAL accepted) and 20x (Key Security Indicators with machine-readable, automatically validated evidence; a 3PAO reviews the validation code; quarterly Ongoing Authorization Reports). Both cite 800-53. The plan keeps 800-53 Rev 5 control ids as the scenario key and the generator emits two profiles from one declaration set:

- **Rev 5** — control implementation statements with status and origination, as markdown and OSCAL SSP; POA&M rows for every unsupported cell and known drift window; CRM rows from the responsibility split.
- **20x** — per KSI, the scenarios that validate it and their latest result, as JSON in the shape the machine-readable docs define; the conformance suite is the validation code.

Constraints: KSI ids are read from FedRAMP's machine-readable repository at lint time, never hard-coded (they were restandardized in February 2026); the impact level and track are inputs to the assess profile, not names in modules or packages. The eighth question in "Who it is for" becomes: can I produce this evidence continuously — monthly under Rev 5, quarterly under 20x — and the answer is the same artifact, dated.

## 5. Altitude fixes

### Fact events are attribute-based, not CUI-shaped
Core defines four fact-event kinds in 800-162 words: subject attribute set or cleared; object attribute set or cleared; subject–object relationship granted or revoked; policy version published. The example's assignment, list membership, marking, decontrol, and office roles are mapped onto these by the example's **fact mapping** — the same mapping the event-store mode already requires from an application. A third party's facts fit the same way. Nothing in core names a program or a marking.

### `scope` returns a filter, not a query
Core defines a small filter language — and, or, not over attribute comparisons, plus `all` and `none`. Adapters return it: rules in code build it directly; Postgres returns `all` (the database narrows); Cerbos's query plan already is one. `turnstile_ecto` compiles it to an Ecto query. Core has no Ecto dependency; a non-Ecto application compiles the filter itself. C13 scope fidelity is a Tier 1 conformance case over the filter language.

### Mediation lives at the Repo seam
The compile-time check on controller actions and context functions is a heuristic and Phoenix-specific. Replace it with a **mediated Repo** in `turnstile_ecto`: every Repo call carries a decision or an explicit exemption, enforced at runtime — `prepare_query/3` for reads (which is also where `scope` is applied), overridden `insert`, `update`, `delete`, `insert_all`, `update_all`, `delete_all` for writes; writes to declared fact schemas record the ledger event in the same transaction. One seam, three guarantees: always invoked, scope fidelity, no fact without an entry. **Audit mode** logs unmediated calls instead of raising; its output is an adopting application's inventory. The generated per-action functions stay for the controller surface — typos still fail to compile. Mediation moves from Phase 5 to Phase 2.

### Two conformance tiers
- **Tier 1, in core, domain-neutral.** The port guarantees over a minimal fixture: deny by default, every call evented, actor kinds enforced, scope fidelity, revocation latency measured, deny on engine failure. Any adapter that passes earns a Tier 1 statement with no example work.
- **Tier 2, in the example, per adapter.** The requirement scenarios over CUI.

### Revocation latency replaces projection lag
With these three adapters the projection is the tables themselves, so "projection lag" is nearly always one transaction. The number a 3PAO asks about is end-to-end: time from a revoking fact or policy change to the first denied request. Tier 1 measures it (write the revocation, poll until deny), decomposed into transaction commit, policy propagation (Cerbos polls its policy store on an interval), read-replica lag, and any per-request cache, and reports it against the FedRAMP-assigned PS-4 value. Per adapter, per build.

### Bring your own adapter, bring your own facts
The surface, stated once in the docs: implement `Turnstile.Adapter` (authorize, check, batch, scope; explain optional); ship a declaration (capability per scenario, default origination, settings, inventory item, measured latency); pass Tier 1; optionally implement `Turnstile.Projection` to consume fact events from a position. The generator prints the statement without a change to core. To bring your own facts, implement the fact mapping. This section is the altitude test: if any of these needs a change in core, core is too low.

## 6. Adopting Turnstile in an existing application (new section)

Starting point: Phoenix with Ecto; a JWT whose claim carries one role; a plug that checks it. Every step ships alone. Run `mix turnstile.assess` after each; the statement is the progress bar.

| Step | Change | What turns green |
|---|---|---|
| 0 | Add `turnstile_core` and `turnstile_ecto`; run the generator; turn the mediated Repo on in audit mode | Nothing yet — the statement is all Not Implemented and the audit log is your inventory of unmediated calls |
| 1 | Strip the role claim from the token. The token carries identity only; a plug resolves roles and attributes per request into the subject | Revocation latency falls from token lifetime to one request — AC-2, PS-4; admission rule "no facts in tokens" |
| 2 | Route the one existing check through the port: rules-in-code adapter, one role, one permission | Behavior identical; every request emits a decision; deny by default holds — AC-3, AU-2, AU-12 |
| 3 | Flip the Repo from audit to enforce; fix the step-0 list | Always invoked — AC-3; AC-25 beyond baseline |
| 4 | Declare the role→permission table: at least a non-privileged and a privileged role; security functions under the privileged one; privileged users get separate accounts; each action names its operation | AC-5, AC-6(1), (2), (5), (10) |
| 5 | Install the Ecto ledger; declare the assignments table (or `users.role`) a fact schema; run the genesis backfill | AC-2(4), AU-9; history begins at the genesis date and the statement says so |
| 6 | Apply `scope` to list queries through the Repo seam | Tenant isolation proven — AC-3; C13 |
| 7 | Support and operator access through the audited override: justified, logged, notified | AC-6(9), AC-2(2) |
| 8 | Re-authentication for sensitive operations from the session's last-authenticated environment fact | IA-11 |
| 9 | `mix turnstile.review`; point-in-time once the ledger has history | AC-2, AC-6(7) |
| 10 | Optional second layer: Postgres RLS for write gates and defense in depth, or Cerbos when policy ownership leaves the engineering team | Origination profile changes; statement regenerated |

**Genesis.** An adopting application has existing state, so the ledger needs a defined origin: every current fact written as an event at position 0, stamped "backfilled from tables on ⟨date⟩ by ⟨migration⟩". Reconcile runs from that point; replay and point-in-time review before genesis are "not available" by construction, and the statement prints the date. The example needs this too, at the Phase 3 transition from ledger mode none to the Ecto ledger.

**`mix turnstile.assess --diff <ref>`** prints what changed between two statements: cells that moved, latency that moved, POA&M items opened or closed. It is the migration's progress and the 20x Ongoing Authorization Report's delta in one command.

**The example is built by walking this path.** Phase 2 starts from tag `v0-jwt-single-role`: a plain Phoenix application with no Turnstile. Each step is a tag; each tag commits its generated statement under `docs/statements/`; the adoption guide is the annotated tag list; CI checks out each tag, regenerates, and diffs against the committed statement so the guide cannot rot. The RLS and Cerbos builds are steps 10a and 10b. Rot is the risk; the CI diff is the mitigation, and if it proves too costly the fallback is committing the "before" application as a fixture rather than a tag.

## 7. Package and phase changes

- `turnstile_ledger` → `turnstile_ecto`: mediated Repo (mediation, scope compilation, fact recording), ledger table and migration, reconcile, replay, genesis backfill.
- `turnstile_rbac` → name for the mechanism (rules in code); RBAC is the model it expresses first, and the docs say so where an adopter will look for the word.
- Mediation: Phase 5 → Phase 2. Phase 2 starts from the `v0` tag.
- Phase 6: OSCAL validated against the FedRAMP templates **and** KSI JSON validated against the machine-readable docs.
- Lint: control ids against the Rev 5 catalog, baseline membership against the Moderate profile, KSI ids against the 20x repo.

## 8. Decision records to add

- RBAC as the first adapter: AC-2(7) and AC-3(7) make it the baseline's default; a single role is not RBAC.
- Two tracks, one catalog: Rev 5 SSP and 20x KSI evidence from one declaration; 800-53 ids as the key.
- Fact events in 800-162 terms; the domain mapped at the boundary.
- Mediation at the Repo seam, at runtime, over a compile-time heuristic.
- `scope` returns a filter language; the Ecto package compiles it.
- Revocation latency, end-to-end, replaces projection lag.
- Genesis backfill as the ledger's origin.
- The example built by migration; tags as the guide; CI diff as the guard.

## 9. Smaller fixes

- **Postgres.** The application role must not own the tables; `FORCE ROW LEVEL SECURITY` on every protected table; session settings set per transaction, because of connection pooling. The migration that creates a policy is the policy version.
- **C10.** "Always succeeds" → succeeds for a subject holding the override permission who supplies a justification; never unconditional.
- **Environment facts.** The port supplies time from a clock behaviour (injectable in tests); callers supply only what the port cannot know, such as last re-authentication. Deny-on-missing applies to the latter, or every decontrol check denies the first time someone forgets `now`.
- **Decision volume.** A setting: all decisions (default, matching the AU-2 web-application parameter) or denies plus writes plus privileged operations; the statement prints which. `review` emits one event per review, not one per subject.
- **Audit record content.** AU-3 needs type, time, source, outcome, identity; decision events should carry a request or session id for correlation (AU-3(1)) and should not dump attribute values (nationality, employment) into the SIEM stream by default — the ledger position is what replay needs.
- **Hash chain.** Put the chain head in every emitted event so the SIEM copy anchors the chain; verification compares the two. A chain that lives only in the database it protects is rewritable by whoever can write that database.
- **Privileged user.** The operator is a separate account, not a flag on a user account — AC-6(2).
- **Naming.** Keep the impact level out of module and package names; it is a profile input.
