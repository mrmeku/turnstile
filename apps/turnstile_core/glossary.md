# Core glossary

The words `turnstile_core` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Reference monitor | The part of a system that checks every access; always invoked, tamperproof, small |
| Subject / object / operation / environment | Who is asking, about what, to do what, under what conditions |
| Attribute | A fact about a subject or object that a rule can test |
| RBAC / ABAC / ReBAC | Rules over roles / over any attribute / over relationships in a graph |
| PEP / PDP / PIP / PAP | Where a request is stopped / where the answer is computed / where attributes come from / where rules are written |
| Port / adapter | The interface in core / an implementation of it for one mechanism |
| Conformance suite | The tests any adapter must pass; the real contract |
| Deny by default / fail closed | No unless a rule says yes / no when the system cannot decide |
| `scope` / `dynamic` | Narrow a query to what the subject may see / the Ecto where-clause fragment it returns, which can only narrow |
| Scope fidelity | `scope` returns exactly the rows `check` would allow |
| Mediated Repo, the seam | A Repo that refuses calls carrying no decision and no exemption |
| Exemption | A named, logged opt-out from mediation, per call, with a reason |
| Protected schema / carried relation | A schema that declares an object type / an association the parent's decision covers |
| Fact event (four kinds) | Subject attribute; object attribute; relationship; policy version, each with old and new |
| Fact mapping | The declaration, column by column, from an application's schemas to the four kinds |
| Projection / projector / checkpoint | How an adapter's state relates to the ledger / the process that drains it / the position it has applied |
| Audit record | A log entry with the shape AU-3 requires |
| Telemetry | Elixir's convention for a library to publish events that handlers consume |
| SIEM | The security team's central log system; a sink |
| Continuous evaluation | Attributes looked up on every check, never cached across requests |
| Revocation latency | Time from a revoking change to the first denial; evidence, measured |
| Environment fact (port-supplied / caller-supplied) | Time from the clock behaviour / facts only the caller knows |
| User / NPE / privileged user | A person / software acting alone / a person who can change the system; the subject's kind |
| Control / enhancement / family | A requirement (AC-2) / an optional sharpening (AC-2(4)) / a group (AC) |
| ODP / FedRAMP-assigned parameter | A blank in a control / a blank FedRAMP fills |
| Baseline / beyond baseline | The subset required at an impact level / cited but not required |
| The line | Opinionated below the port; above it the database is reached only through the ledger behaviour and `around_query/3`, checked at compile time |
| Declaration / scenario / capability | What an adapter or thin app states about itself / a cited test / a rule's level with the enforcing component |
| Tier 1 / Tier 2 | Port guarantees over a neutral fixture / CUI scenarios per thin app |
| `review` | Who can do what, today or on a date |
| Configuration override | The keyword list `Turnstile.Test.with_config/1,2` puts in a process's dictionary, read by the resolver from the caller and its `$callers` chain over the boot struct |
| Counter name | The `ledger_counter` field of the configuration: which row of `turnstile_ledger_counter` a transaction takes positions from; `default` in production, a per-test row in the sandbox |
