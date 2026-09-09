# Example glossary

The words `turnstile_example` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Document | The protected record: a title, a designating office, a program, a decontrol date, a marking, portions, and proposals |
| Portion | One part of a document with a marking of its own; the redacted read returns the portions the subject may read |
| Marking | The categories, controls, and releasable-to list a portion carries and a document's banner unions |
| Banner | A document's marking: the union of its portions' markings, enforced at write time (C4) |
| Control | One dissemination control: `federal_only`, `no_foreign`, `named_list`, or `releasable_to`, each a test on the subject (C2) |
| Category | A CUI category; a specified category implies controls that count as declared (C3) |
| Decontrol | The date after which C2 to C4 no longer apply to a document; C1 still does (C5) |
| Named list | The users a marking names directly; membership grants nothing beyond C1 (C6) |
| Program | The unit an assignment belongs to; an open program gives lawful purpose to its members (C1) |
| Assignment | A user's role in a program: `member` or `lead` |
| Office role | A user's role in an office: `designator` or `approver` (C7, C9) |
| Designating office | The office that designated a document and receives its override reports |
| Proposal | A marking change one designator proposed and a different approver approves (C9) |
| Override | A privileged read outside C1, with a justification, its own event, and a report (C10) |
| Privileged account | An account of kind `privileged`, separate from the person's user account, that may hold the override permission |
| Re-authentication | The `reauthenticated_at` fact the identity layer supplies; a C7 operation needs it within the window (C8) |
| Window | The re-authentication window, `Example.Sessions.window/0`, the organization's parameter for IA-11 |
| Audit store | The hash-chained records of every decision and override event, verified as a chain (AU-9) |
| Access review | The report of who may do what on each agency's documents and of every privileged account (AC-2) |
| Fixture | The world every scenario starts from: two agencies, offices, programs, categories, and one account per role |
| Scenario | One row of the reference's table, defined in a thin application's test module by `use Example.Scenarios` |
