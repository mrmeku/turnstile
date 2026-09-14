# Core glossary

The words `turnstile` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Reference monitor | The part of a system that checks every access; always invoked, tamperproof, small |
| Subject / object / operation / environment | Who is asking, about what, to do what, under what conditions; a subject is a `{kind, id}` tuple, an object a `{type, id}` tuple, and the environment a map of the caller's facts with `now` from the configured clock beside them |
| Attribute | A fact about a subject or object that a rule can test |
| RBAC / ABAC / ReBAC | Rules over roles / over any attribute / over relationships in a graph |
| PEP / PDP / PIP / PAP | Where a request is stopped / where the answer is computed / where attributes come from / where rules are written |
| Port / adapter | The interface in core / an implementation of it for one mechanism |
| Conformance suite | The tests any adapter must pass; the real contract |
| Deny by default / fail closed | No unless a rule says yes / no when the system cannot decide |
| `scope` / `dynamic` | Narrow a query to what the subject may see / the Ecto where-clause fragment it returns, which can only narrow |
| Scope fidelity | `scope` returns exactly the rows `check` would allow |
| Mediated Repo, the seam | A Repo that refuses calls carrying no decision and no exemption |
| Surface / bucket | Every function `use Ecto.Repo` defines, by name and arity / the one of query, write, raw, or plumbing each sits in |
| Mediation | The `turnstile:` option resolved for one call: the decision or exemption, the caller, and the schemas the decision carries |
| Ambient mediation | The parent write's mediation, held in the process for the nested association writes Ecto makes without the option |
| Caller | The module that called the Repo, read from the stack past the Repo, the seam, Ecto, and the standard library |
| Exemption (declared / library) | A named, logged opt-out from mediation, per call, with a reason / the same from a `Turnstile.*` caller, or every call on an owner-role repo |
| Owner-role repo | `use Turnstile.Repo, role: :owner`: the library's own channel, library-exempt on every call, recording nothing |
| RepoCase | The conformance test that holds a Repo to the surface and refuses each non-plumbing function without a decision |
| Protected schema / carried relation | A schema that declares an object type / an association the parent's decision covers |
| Audited schema / kind | A schema that declares what kind of thing its rows are / `:user`, `:group`, `:role`, or `:entity`, which is the kind a change event carries |
| Fact kind (three) | Subject attribute; object attribute; relationship: what a declared fact column holds |
| Fact mapping | The declaration, column by column, from an application's schemas to the three kinds |
| Change event | One single-row write to an audited schema as telemetry: `[:turnstile, :change]`, carrying the operation, the kind, the row, each changed fact field as old and new, who asked, and when |
| Settle | Bringing an adapter's own state into step with the tables, which an adapter reading those tables has nothing to do for |
| Audit record | A log entry with the shape AU-3 requires |
| Telemetry | Elixir's convention for a library to publish events that handlers consume |
| Consumer | A handler that stores what an event carries; the library emits and the system stores, so a consumer is the system's, not the library's |
| SIEM | The security team's central log system; the worked consumer |
| Continuous evaluation | Attributes looked up on every check, never cached across requests |
| Revocation latency | Time from a revoking change to the first denial; evidence, measured |
| Environment fact (port-supplied / caller-supplied) | Time from the configured clock / facts only the caller knows |
| User / NPE / privileged user | A person / software acting alone / a person who can change the system; the subject's kind |
| Control / enhancement / family | A requirement (AC-2) / an optional sharpening (AC-2(4)) / a group (AC) |
| ODP / FedRAMP-assigned parameter | A blank in a control / a blank FedRAMP fills |
| Baseline / beyond baseline | The subset required at an impact level / cited but not required |
| The line | Opinionated below the port; above it the database is reached only through `around_query/3`, checked at compile time |
| Declaration / scenario | What a schema states about itself through `use Turnstile.Schema` / one row of the Tier 2 table: an id, a sentence, a group, the controls cited, and what it tests |
| Tier 1 / Tier 2 | Port guarantees over a neutral fixture / CUI scenarios per thin app |
| `review` | Who can do what today |
| Configuration override | The keyword list `Turnstile.Test.with_config/1,2` puts in a process's dictionary, read by the resolver from the caller and its `$callers` chain over the boot struct |
| Answer / `meta` | What an adapter says about one question: a verdict, a reason in one word, the version of the rules, and `meta` / the adapter's own map beside the reason, where what only one adapter can say travels |
| Edge | A struct's map form: `to_map/1` and `from_map/1`, atoms as strings, modules by name, references as maps, times in ISO 8601 |
| Decision event | One port call as telemetry: `[:turnstile, :decision]`, its duration the one measurement, and who asked, what was answered, and which adapter answered its metadata |
| Rule table | The fake adapter's `Agent`: entries allowing one subject, or any, one operation, on one object, or any of a type |
| World | A population of the neutral fixture: accounts with clearances, folders, items, and memberships; the generators draw one, the template writes it through the seam |
| Seed / outage hook | The `Turnstile.Conformance.Seed` module a template option names: `seed/1` loads a world into an adapter's own state, `outage/0` makes its engine unreachable |
| Shape test | A test of what a call does, not what it answers: the queries it runs and the records it emits |
