# Turnstile on Cerbos

The adapter whose rules are policy files and whose decisions come from a sidecar reading them: `Turnstile.Cerbos`. The sidecar is Cerbos 0.55.0, pinned in the flake (`docs/reference.md` §12), and it runs beside the application on the same host. Its configuration entry carries `address:`, the host and port the sidecar answers on, and nothing else, because the address is where a process runs; what the adapter may read comes from the binding.

- `Turnstile.Cerbos`: the `Turnstile.Adapter` implementation. `check`, `authorize`, `batch`, and `explain` read the declared attribute values through the bound repo and then ask the sidecar once for every object named, where an effect of allow is allowed by the policy the sidecar matched and anything else is a denial. `scope` asks for a query plan and compiles the filter it answers into a `dynamic` over the object type, and a plan it cannot express is an error the caller answers by asking per row, which is what a rule enforced this way records as limited. It implements no `around_query/3`, since a sidecar carries no session state a repo call would have to run under. The adapter needs no ledger, and its scope cap is none, since a plan holds no limit of its own.
- `Turnstile.Cerbos.Binding`: what the adapter needs beyond the address. The mediated repo the attribute values are read through, the module that declares those attributes, the policy directory and the commit the sidecar is serving, who wrote and approved that commit, and the path of the sidecar's decision log. `bind/1` validates them once at boot beside the configuration's boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `use Turnstile.Cerbos.Attributes`: the declaration. `principal :kind, schema: Schema do ... end` names a subject kind and the schema whose row is the subject; `resource :type, schema: Schema do ... end` names an object type and the schema whose rows are the objects; `attribute name, column: :column` or `attribute name, subquery: &Module.function/1` maps a name the policies read to where its value comes from (`Turnstile.Cerbos.Attribute`). A column is what the row holds. A subquery is a function of the subject returning a query that selects `%{id: ..., value: ...}` with the value as text, so a value that depends on who is asking is one query rather than a list of ids.
- `Turnstile.Cerbos.Values`: the declared values read as a library caller, one query for a kind's columns and one per subquery. Every declared attribute is sent, a column with nothing in it as null and a subquery that selected nothing as the empty list, because a sidecar told nothing about an attribute records an evaluation error against the request where the answer is sound. A value crosses to JSON as itself where JSON has it and as text where it does not.
- `Turnstile.Cerbos.Request` and `Turnstile.Cerbos.Client`: the bodies the sidecar reads, and the sidecar over HTTP and JSON. The transport is `httpc` and the encoder is Elixir's `JSON`, both of which ship with the platform, so this adapter adds no dependency to the application that takes it. Every call carries a deadline and emits one telemetry event, which is how a shape test counts the engine's own calls (`docs/reference.md` §7).
- `Turnstile.Cerbos.Decide`: the effects the sidecar answered turned into answers. A denial names the policy the sidecar evaluated where it named one, and is not read as a rule that denied, since the sidecar names a policy whether a rule denied or no rule allowed. A resource the sidecar answered nothing about is denied by default.
- `Turnstile.Cerbos.Plan`: the query plan compiled to a `dynamic`. A plan that admits every row is `true`, a plan that admits none is a denial, and a conditional plan is an expression tree over `request.resource.attr.<name>` compiled against the declarations: a column attribute becomes a comparison on the column, a subquery attribute becomes membership in the ids the subquery selects. An expression outside that set is neither guessed at nor dropped, because a plan narrowed by half returns rows the policy denies and a plan discarded returns nothing where the policy allows.
- `Turnstile.Cerbos.Coverage`: declared-fact coverage. It walks the compiled query, subqueries included, collects every field reference by the schema of the source it names, and fails with the column's name on a read that no `fact`, `relationship`, primary key, or carried foreign key declares. A fragment cannot be walked and is a finding of its own.
- `Turnstile.Cerbos.Version`: the policy version is the commit the binding names, and the content is the policy files as text, each preceded by its path, carried by value under the configured cap and left as a pointer to the directory and the commit otherwise. The content hash is the digest of that text either way, so a directory changed without a new commit reads as a hash that no longer matches. `Turnstile.Cerbos.publish/0` appends the version when the ledger's latest for this adapter is older or missing, inside the ledger's transaction when the ledger offers one, so many nodes booting at once append it once; in ledger mode none it emits `[:turnstile, :cerbos, :policy_version]` and appends nothing.
- `Turnstile.Cerbos.Propagation`: the `policy_propagation` component of revocation latency (`docs/reference.md` §4), measured. Writing policy text into the directory and putting back what was there is a file operation; the measurement takes the publish as a function, runs it, and polls with `Turnstile.Test.poll/2` until the caller's question answers the new way. The poll interval is the floor of any number it produces, and nothing here asserts one.
- `Turnstile.Cerbos.Decisions`, `Turnstile.Cerbos.Decisions.Line`, and `Turnstile.Cerbos.Finding`: the sidecar's decision log read back and set beside what the port recorded. The log is a file of JSON objects, one per line, and each becomes as many lines as it holds answers. Reconciliation matches on who asked, which operation, and which object, since the sidecar is never told the identifier the port gave the call, and reports a decision the log holds that no record matches, a record no line holds, and a pair that agree on the question and disagree on the answer. Reading it is the caller's move and happens on no request path.
- `Turnstile.Cerbos.Replay`: a policy version put back in a policy directory of its own, for a sidecar the caller raised and throws away, since a sidecar reads one directory and the running one is answering other questions from its own. Every policy file of another version is taken out of that directory. Asking a stored decision again takes the attribute values from the record rather than from the tables, so state that moved since cannot reach the answer.
- `priv/conformance/`: the policies for the neutral fixture and the attribute declarations behind them, which the conformance suite runs against. The test run compiles the module and the sidecar reads the policies; an application loads neither.

`glossary.md` defines the words this package owns. The package's `lib` depends on `turnstile_core`, `ecto`, `nimble_options`, and `telemetry`; `ecto_sql`, `postgrex`, and `muontrap` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## What the sidecar is told

The declarations bound the request in both directions. What reaches the sidecar is the declared attributes and a role per subject kind, so a policy says which kinds it answers for by naming roles, and nothing else about the subject travels. The environment's caller-supplied facts do not travel at all: a policy cannot come to depend on a value no declaration names, and a value no declaration names cannot reach a decision that a ledger would later have to replay.

The same declarations bound the other direction. A query plan is compiled over declared attributes alone, and the columns behind them are what `Turnstile.Cerbos.Coverage` sets against the fact declarations of their schemas.

## A rule the query plan does not carry

A plan request answers with a filter over the resource attributes the sidecar could not resolve. Where every operand of that filter is a declared attribute compared in a way this adapter expresses, the filter is one query. Where it is not, `scope` fails with the reason the plan could not be expressed and emits `[:turnstile, :cerbos, :scope_fallback]`, and the caller asks the port per row instead. That is the level a rule enforced through such a plan declares, with the operator the plan used as the note.

## Binding at boot

After the configuration boots with `adapter: {Turnstile.Cerbos, address: "127.0.0.1:3592"}`, the application binds and publishes:

```elixir
{:ok, _binding} =
  Turnstile.Cerbos.Binding.bind(
    repo: MyApp.Repo,
    attributes: MyApp.Attributes,
    policies: "priv/policies",
    commit: "9c1f4ae",
    author: "the policy owner",
    approval: "the change record",
    decision_log: "/var/log/cerbos/decisions.log"
  )

{:ok, _event} = Turnstile.Cerbos.publish()
```

The commit comes from the repository the policy files live in, so the application is told which commit it is serving rather than deriving one: a sidecar reading a directory has no opinion about history, and the `version` field inside a policy file is not history either, since it runs variants of a policy side by side.
