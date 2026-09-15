# Turnstile on Cerbos

The adapter whose rules are policy files and whose decisions come from a sidecar reading them: `Turnstile.Cerbos`. The sidecar is Cerbos 0.55.0, pinned in the flake (`docs/contributing.md` §1), and it runs beside the application on the same host. The policy files have an owner of their own, revocation of a fact is one commit, a rule change waits on the sidecar's reload, and the boundary cost is one sidecar. The configuration entry carries `address:`, the host and port the sidecar answers on, and nothing else; what the adapter may read comes from the binding.

- `Turnstile.Cerbos`: the `Turnstile.Adapter` implementation. `decide` reads the declared attribute values through the bound repo, one query for a kind's columns and one per subquery, and then asks the sidecar once. Every declared attribute is sent, a column with nothing in it as null and a subquery that selected nothing as the empty list, because a sidecar told nothing about an attribute records an evaluation error against the request where the answer is sound. An effect of allow is allowed by the policy the sidecar matched, and anything else is a denial that names the policy the sidecar evaluated where it named one; a resource it answered nothing about is denied by default. `scope` asks for a query plan and compiles the filter it answers into a `dynamic` over the object type: a plan that admits every row is `true`, a plan that admits none is a denial, and a conditional plan is an expression tree over `request.resource.attr.<name>` compiled against the declarations, where a column attribute becomes a comparison on the column and a subquery attribute becomes membership in the ids the subquery selects. An expression outside that set is neither guessed at nor dropped: `scope` fails with the reason, emits `[:turnstile, :cerbos, :scope_fallback]`, and the caller asks per row. It implements no `around_query/3`, since a sidecar carries no session state a repo call would have to run under. The scope cap is `:none`.
- `Turnstile.Cerbos.Binding`: what the adapter needs beyond the address. The mediated repo the attribute values are read through, the module that declares those attributes, the policy directory and the commit the sidecar is serving, and who wrote and approved that commit. `bind/1` validates them once at boot beside the configuration's boot; `override/1,2` binds per process, read through `$callers`, for tests.
- `use Turnstile.Cerbos.Attributes`: the declaration. `principal :kind, schema: Schema do ... end` names a subject kind and the schema whose row is the subject; `resource :type, schema: Schema do ... end` names an object type and the schema whose rows are the objects; `attribute name, column: :column` or `attribute name, subquery: &Module.function/2` maps a name the policies read to where its value comes from. A column is what the row holds. A subquery is a function of the subject and the environment returning a query that selects `%{id: ..., value: ...}` with the value as text, so a value that depends on who is asking, or on the moment the port stamped the request with, is one query rather than a list of ids. An `environment` block declares the request-time facts that travel beside `now`.
- `Turnstile.Cerbos.Request` and `Turnstile.Cerbos.Client`: the bodies the sidecar reads, and the sidecar over HTTP and JSON. The transport is `httpc` and the encoder is Elixir's `JSON`, both of which ship with the platform, so this adapter adds no dependency to the application that takes it. Every call carries a deadline and emits one telemetry event, which is how a shape test counts the engine's own calls.
- `Turnstile.Cerbos.Coverage`: declared-fact coverage. It walks the compiled query, subqueries included, collects every field reference by the schema of the source it names, and fails with the column's name on a read that no `fact`, `relationship`, primary key, or carried foreign key declares. A fragment cannot be walked and is a finding of its own.
- `Turnstile.Cerbos.Version`: the policy version is the commit the binding names, and the content is the policy files as text, each preceded by its path, carried by value under the configured cap and left as a pointer to the directory and the commit otherwise. The content hash is the digest of that text either way, so a directory changed without a new commit reads as a hash that no longer matches. `Turnstile.Cerbos.publish/0` emits `[:turnstile, :cerbos, :policy_version]` carrying the version, once per call, and stores nothing.
- `Turnstile.Cerbos.Propagation`: the `policy_propagation` component of revocation latency, measured. Writing policy text into the directory and putting back what was there is a file operation; the measurement takes the publish as a function, runs it, and polls until the caller's question answers the new way. The poll interval is the floor of any number it produces, and nothing here asserts one.
- Test support, compiled and never published: the attribute declarations for the neutral fixture, the subqueries behind them, and the versions module that swaps a tightened policy in and out, beside `priv/conformance/`, which holds the policies the sidecar reads.

The package's `lib` depends on `turnstile`, `ecto`, `nimble_options`, and `telemetry`; `ecto_sql`, `postgrex`, and `muontrap` serve its own tests only, and Boundary checks that no call from `lib` reaches them.

## Mechanism per rule shape

| Rule shape | Mechanism |
|---|---|
| A test on the subject | a principal attribute, a column of the subject's schema or a subquery of the subject and the environment, read at the call and sent with the request |
| A test on the row | a resource attribute, sent the same way; a policy cannot depend on a value no declaration names |
| A test on the moment or a request-time fact | the `environment` principal attribute, `request.principal.attr.environment.now` and one field per declared fact, from the port's clock rather than the sidecar's; every moment is cut to the second, because a policy compares them as text and a plan compares a column of the same moment in the database |
| A rule over a whole type | the sidecar's query plan compiled over declared attributes alone; an operator the compiler does not carry is refused rather than narrowed |
| A write gate | the seam refuses a write with no decision for the operation before the policy is asked |

What reaches the sidecar is the declared attributes and a role per subject kind, so a policy says which kinds it answers for by naming roles, and nothing else about the subject travels.

## Latency

Two components. Commit, for a fact: the attribute values are read at each request. Policy propagation, for a rule: the interval from a file landing in the directory to the sidecar answering by it, which `Turnstile.Cerbos.Propagation` measures. The conformance suite prints both beside its run and asserts nothing about them.

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
    approval: "the change record"
  )

{:ok, _event} = Turnstile.Cerbos.publish()
```

The commit comes from the repository the policy files live in, so the application is told which commit it is serving rather than deriving one: a sidecar reading a directory has no opinion about history, and the `version` field inside a policy file is not history either, since it runs variants of a policy side by side.
