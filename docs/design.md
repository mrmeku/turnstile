# Design

*What Turnstile is, what its port says, what the seam is for, and where each thing lives. This is the document the others assume.*

## 1. What Turnstile is

Turnstile is the minimal port-and-adapters API an Elixir application needs to express its authorization for a FedRAMP Rev 5 Moderate target. It ships with four adapters, roles in code, Postgres row-level security, Cerbos, and OpenFGA, so a reader can see what each decision strategy costs: in adapter code, and in how the application has to express its needs.

The requirements come from NIST SP 800-53 Rev 5 as the FedRAMP Rev 5 Moderate baseline selects and parameterizes them. `docs/requirements.md` lists the lines that reach this library and what answers each. The word "minimal" is measured: the port carries what the example application needs plus what the conformance laws need, and whatever neither reaches is removed.

Five commitments hold across every package.

1. The library emits records and stores nothing. No statement, no history, no log lives in a library package. A consumer attaches a handler and owns the record.
2. A decision lives in a module that a test can call directly, and a module that touches the world does nothing else.
3. The surface is what a test can assert. A guarantee that no test can reach is not a guarantee this repository makes.
4. Each tool enforces only what it can see. The seam sees repo calls; the database sees rows; a Credo check sees source. None of them claims the others' ground.
5. The conformance suites are the asset. Every adapter passes the same laws against its real engine, and the laws are named by the requirement line they answer.

## 2. The port

The port is `Turnstile`, four functions, and nothing else.

| Function | Answers | Returns |
|---|---|---|
| `authorize(subject, operation, object, opts)` | May this subject perform this operation on this object, and under which decision | `{:ok, %Turnstile.Decision{}}` or `{:error, %Turnstile.Error{}}` |
| `check(subject, operation, object, opts)` | The same question as a boolean, for a branch that does not go on to the repo | `true` or `false` |
| `scope(subject, operation, object_type, opts)` | Which objects of a type may this subject perform this operation on | `{dynamic, %Turnstile.Decision{}}`, an Ecto `dynamic` that can only narrow |
| `review(reviewer, subjects, operation, object_type, opts)` | For each of these subjects, which objects of a type may it perform this operation on, asked by a reviewer | `%{subject => {dynamic, %Turnstile.Decision{}}}` |

**The vocabulary** is NIST SP 800-162's. A subject is `{kind, id}`, where kind is `:user`, `:non_person_entity`, or `:privileged`, and a kind the port does not know is refused before any adapter is called. An object is `{type, id}`, and a decision over a whole type, which `scope` and `review` make, carries `nil` for the id. An operation is an atom. The environment is a map of the facts only the caller knows, given as `opts[:env]`, with `now` stamped from the configured clock beside them, so a decider reads the moment of the request from the environment rather than from a clock of its own.

**Options** are `env`, the environment map, and `operation_id`, one identifier shared by every event of one operation; the port generates one where the caller gives none.

**The structs.** `%Turnstile.Answer{verdict, reason, version, meta}` is what an adapter says about one question: `:allow` or `:deny`, a reason in one word from a fixed list, the version of the rules that answered, and the adapter's own map beside them. `%Turnstile.Decision{id, subject, object, operation, verdict, reason, adapter, policy_version, operation_id, at}` is what the port said, stamped, and is the value the seam accepts. `%Turnstile.Error{reason, detail}` is the one exception: a denial's reason where the failure follows a denial, and `:unsupported`, `:invalid`, or `:unmediated` where it is the library's.

**Deny by default and fail closed.** The port never raises on the request path. An adapter that raises, or answers that its engine is unreachable, produces a denial whose decision event carries the exception. An operation no rule names is denied.

**Review.** `review` asks `scope` once per subject under the reviewer's operation id, stamps each decision for its subject, and emits it, then emits the reviewer's own `:scoped` decision over `{type, nil}`. A caller runs each subject's rule as a query carrying that subject's decision, which is what lets an adapter that binds the subject at query time answer a review at all.

## 3. The adapter behaviour

`Turnstile.Adapter` is what a mechanism implements.

| Callback | Required | What it does |
|---|---|---|
| `decide(subject, operation, object, environment, options)` | yes | Answers one question with a `%Turnstile.Answer{}`; `authorize` and `check` both route here |
| `scope(subject, operation, object_type, environment, options)` | yes | Answers a `dynamic` over the object type, or an error |
| `scope_cap()` | yes | The most objects one `scope` can name, or `:none` where the rule is a predicate rather than a list |
| `around_query(query_or_changeset, decision, continue)` | optional | Runs around every mediated call, given the decision in force; where an adapter binds the subject at query time |
| `options_schema()` | optional | The `NimbleOptions` schema of the adapter's own configuration |
| `settle()` | optional | Brings the adapter's own state into step with the tables; `:none` where it reads the tables directly |

An adapter is domain-free. It names no schema of any application and no rule id of the example. What a rule reads, it reads through the facts the application declared on its schemas (`docs/events.md` §3), and the coverage tests each adapter carries hold it to that.

## 4. The seam

`use Turnstile.Repo`, after `use Ecto.Repo`, makes a repo that refuses any call on a protected schema that carries neither a decision nor an exemption. Its purpose is log completeness: every read and every write of a protected schema is recorded against the subject and the decision it ran under, so an unmediated call is refused because it would be an unlogged access. The same reason refuses a bulk write to an audited schema, which has no old value to record. The seam claims nothing beyond this. It is not a reference monitor and no control this library answers asks for one.

**What a schema declares.** `use Turnstile.Schema` gives a schema `object_type/1`, which makes it protected, `carries/1`, the associations the parent's decision covers, `audited/1`, what kind of thing its rows are, and `fact/2` and `relationship/1`, which columns a rule may read and what they mean. `docs/events.md` §3 has the declarations in full.

**The surface** is every function `use Ecto.Repo` defines, by name and arity, each in one of four buckets: query (`all`, `one`, `get`, `get_by`, `reload`, `aggregate`, `exists?`, `stream`, `preload`, `all_by`, and the bulk `update_all` and `delete_all`), write (`insert`, `update`, `delete`, `insert_or_update`, `insert_all`, and their raising forms), raw (`query`, `query_many`, and their raising forms), and plumbing (transactions, checkout, configuration, and the rest). Query and write calls are mediated. A raw call is refused unless it carries an exemption. Plumbing passes.

**Matching.** A call is judged by its root source, the schema the query is from or the changeset is of. A protected root needs a decision whose object type is the root's. A preload needs a decision of its own unless the parent carries the association. A query joining several protected sources is judged by its root, and the other sources must be carried by it. A schema that declares no object type passes; that is how `schema_migrations` and the framework's own tables pass without an exemption.

**Exemptions**, one struct: `%Turnstile.Exemption{on, caller, reason, kind}`. Per call, `turnstile: {:exempt, reason}` with a non-empty reason, recorded with the root source and the calling module. From a `Turnstile.*` caller, `turnstile: {:exempt, :library}`, which the seam accepts by reading the caller off the stack. `use Turnstile.Repo, role: :owner` is the library's own channel: it runs migrations, it records nothing, and every call on it is library-exempt.

**Refusal** raises `%Turnstile.Error{reason: :unmediated}` carrying the function and arity, the root source, the decision's object type where there was one, and the caller. There is no mode that logs instead of raising.

**Extension points**, for an adapter: `prepare_query/3`, which the seam defines and an adapter's rewrite runs inside; the write overrides; the raw wrap; and `around_query/3`. `turnstile_postgres` uses the last to open a transaction where none is open and bind the subject's session settings on every call.

## 5. The events

Three telemetry events, each carrying what an OCSF 1.3.0 record needs without inventing a value, and none of them stored by the library.

| Event | Published | Answers |
|---|---|---|
| `[:turnstile, :decision]` | after every port call | authorization checks; the execution of privileged functions, by subject kind |
| `[:turnstile, :change]` | inside the transaction of a single-row write to an audited schema | data changes, deletions, and permission changes; account creation, modification, and removal |
| `[:turnstile, :access]` | after every mediated read of a protected schema | data access, naming the rows returned and the decision they were read under |

Each adapter also publishes a policy-version event when a version is put in force. `docs/events.md` has every payload and the guarantees the seam makes about them.

## 6. Packages and placement

| Package | Published | What it holds |
|---|---|---|
| `turnstile` | yes | The port, the behaviour, the seam, the schema declarations, the events, the conformance suites; runtime deps `ecto`, `telemetry`, `nimble_options`, `stream_data`, and a test in its suite holds that count |
| `turnstile_credo` | yes | Two static checks: no raw SQL outside an allowlist, no `use Ecto.Repo` without the seam |
| `turnstile_rbac` | yes | Roles in code: a policy module of grants and predicates over the application's tables |
| `turnstile_postgres` | yes | Row-level security: policies the migrations write, session settings bound per call |
| `turnstile_cerbos` | yes | A sidecar policy engine, fed attributes the application declares |
| `turnstile_fga` | yes | OpenFGA: a tuple store kept in step with the tables by an outbox and a relay |
| `turnstile_dev` | no | The ephemeral Postgres cluster, the sandbox, the schema dump, the structure test, and the engine runners the suites start |
| `example` | no | The CUI domain, its rules C1 to C13, and the scenario bodies every binding shares |
| `example_rbac`, `example_postgres`, `example_cerbos`, `example_fga` | no | One binding of the example to one adapter, with that adapter's migrations, policies, or model |

**Three places** inside a package's `lib/`. The root holds the package's public modules, with `@moduledoc`. `core/` holds modules that decide, hold nothing, and call nothing outside the package, at 100 percent line coverage, `@moduledoc false`. `adapter/` holds modules that touch a database, an engine, a file, a clock, or a process, `@moduledoc false`. Calls run one way: the root reaches `adapter/` and `core/`, and `adapter/` reaches `core/`. A path names its module. Errors, structs, and behaviours sit at the root. Adapters may call adapters in their own package and nothing in another package's interior. `boundary` and the structure test in `turnstile_dev` enforce what the compiler can see; `mix xref graph --label compile-connected --fail-above 0` and `--format cycles --fail-above 0` hold the dependency graph flat.

Library packages ship migration helpers; migrations exist only in the thin applications, one set each. What each rule of the example is enforced by is stated in the thin application, never in an adapter package.

## 7. Configuration

`%Turnstile.Config{}` is validated once at boot from a `NimbleOptions` schema, put in `:persistent_term`, and is the only runtime configuration the library reads.

| Field | Type | Default |
|---|---|---|
| `adapter` | `module` or `{module, keyword}`, the options validated by the adapter's own `options_schema/0`; a bare module means `[]` | required |
| `clock` | a zero-arity function answering the current time in UTC | `&DateTime.utc_now/0` |
| `caps` | keyword with one key, `policy_content_bytes`, the policy text a version carries by value before a pointer takes its place | `[policy_content_bytes: 65_536]` |

Adapter options: `turnstile_cerbos` takes an `address`; `turnstile_fga` takes an `endpoint`, a `store_id`, a `model_id`, and a `client`; `turnstile_rbac` and `turnstile_postgres` take none. Tests override any field through `Turnstile.Test.with_config/1`, which puts the override in the process dictionary, and the resolver checks `self()` and then the `$callers` chain before the boot struct.

## 8. What would reverse a decision

- A team asks for replay: a consumer that stores change events is the adopter's to write, outside this repository.
- A package passes eighty modules: the structure test grows a rule before the shape is lost.
- Durable audit at low volume is wanted inside the application: a consumer over Oban, still the adopter's.
- The seam's coverage of the repo cannot be shown for some call: the enforcement moves to the data layer, as the Postgres adapter already does for writes.

## 9. Words

| Term | Meaning |
|---|---|
| Subject / object / operation / environment | Who is asking, about what, to do what, under what conditions |
| Subject kind | `:user`, a person; `:non_person_entity`, software acting alone; `:privileged`, a person who can change the system |
| Attribute, fact | A value about a subject or object that a rule can test; declared on a schema with `fact/2` |
| Grant | A row that gives a subject a role on an object; declared with `relationship/1` |
| Port / adapter | The four functions in `turnstile` / an implementation of `Turnstile.Adapter` for one mechanism |
| Answer / decision | What an adapter says about one question / what the port said, stamped and identified |
| Deny by default / fail closed | No unless a rule says yes / no when the system cannot decide |
| `scope` / `dynamic` | Narrow a query to what the subject may see / the Ecto where fragment it returns, which can only narrow |
| Scope fidelity | `scope` returns exactly the rows `check` would allow |
| `review` | Who can do what, today, asked by a reviewer |
| The seam, mediated repo | A repo that refuses calls carrying no decision and no exemption |
| Surface / bucket | Every function `use Ecto.Repo` defines, by name and arity / the one of query, write, raw, or plumbing each sits in |
| Mediation | The `turnstile:` option resolved for one call: the decision or exemption, the caller, and the schemas the decision carries |
| Ambient mediation | The parent write's mediation, held in the process for the nested association writes Ecto makes without the option |
| Caller | The module that called the repo, read from the stack past the repo, the seam, Ecto, and the standard library |
| Exemption (declared / library) | A named, recorded opt-out from mediation, per call, with a reason / the same from a `Turnstile.*` caller, or every call on an owner-role repo |
| Owner-role repo | `use Turnstile.Repo, role: :owner`: the library's own channel, library-exempt on every call, recording nothing |
| Protected schema / carried relation | A schema that declares an object type / an association the parent's decision covers |
| Audited schema / kind | A schema that declares what kind of thing its rows are / `:user`, `:group`, `:role`, or `:entity` |
| Fact kind | Subject attribute, object attribute, or relationship: what a declared column holds |
| Decision event / change event / access event | One port call / one single-row write to an audited schema / one mediated read, each as telemetry |
| Policy version | The rules an adapter decides under, with an author, an approval, and a content hash, announced by an event when put in force |
| Consumer | A handler that stores what an event carries; the library emits and the system stores |
| SIEM | The security team's central log system; the example's consumer holds its records in memory |
| Settle | Bringing an adapter's own state into step with the tables, which an adapter reading those tables has nothing to do for |
| Continuous evaluation | Facts read on every check, never cached across requests |
| Revocation latency | Time from a revoking change to the first denial; measured and printed, never asserted |
| Configuration override | The keyword list `Turnstile.Test.with_config/1,2` puts in a process's dictionary, read from the caller and its `$callers` chain over the boot struct |
| Rule table | The fake adapter's `Agent`: entries allowing one subject, or any, one operation, on one object, or any of a type |
| World / seed | A population of the neutral fixture the conformance laws run over / the module that loads one into an adapter's own state |
| Law | One conformance test, named by a requirement id and a sentence, run by every adapter |
| Scenario | One row of the example's table: an id, a sentence, the rule it shows, and the controls it cites |
| Shape test | A test of what a call does rather than what it answers: the queries it runs and the events it emits |
| Thin application | One of the four applications that bind the example to an adapter |
| Control / enhancement / family | A requirement (AC-2) / an optional sharpening (AC-2(4)) / a group (AC) |
| ODP / FedRAMP-assigned parameter | A blank in a control / a blank FedRAMP fills |
| Baseline | The subset of the catalog an impact level requires |
