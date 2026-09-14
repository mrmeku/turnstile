# Turnstile

Turnstile is an Elixir authorization library built for FedRAMP Moderate assessment-readiness. An application asks one port, the `Turnstile` module, whether a subject may perform an operation on an object; an adapter answers from roles in code, from Postgres row-level security, from a Cerbos sidecar, or from an OpenFGA store; a mediated Ecto Repo refuses any query that carries no decision; and every write to an audited schema publishes a change event naming what changed, so access can be reviewed and the record of a decision read beside the facts it was taken under.

## Asking the port

A context function asks, and hands what it gets back to the seam. Nothing reaches a protected table any other way.

```elixir
with {:ok, decision} <- Turnstile.authorize(subject, :read, object, []) do
  Repo.get(Document, id, turnstile: decision)
end
```

A list is the same question over a table rather than a row, and the answer is a rule the query carries.

```elixir
{rule, decision} = Turnstile.scope(subject, :read, :document, [])
Repo.all(from(d in Document, where: ^rule), turnstile: decision)
```

## The four adapters

One port, four mechanisms. Each is a package of its own, and each has a thin application that binds it to the same example domain and whose README says what each rule of that domain is enforced by. `docs/reference.md` §4 carries this table and the notes per adapter.

| Adapter | Package | Example application | Enforcement | Explains | Revocation latency components | Rules live in | Boundary cost |
|---|---|---|---|---|---|---|---|
| RBAC in code | `turnstile_rbac` | [`example_rbac`](apps/example_rbac/README.md) | the application's discipline, backed by the seam | the clause | commit | Elixir modules; a deploy is a policy version | none |
| Postgres row-level security | `turnstile_postgres` | [`example_postgres`](apps/example_postgres/README.md) | the database; write gates need no application code (a printed note, not a rule) | verdict only | commit | migrations; a migration is a policy version | none new |
| Cerbos | `turnstile_cerbos` | [`example_cerbos`](apps/example_cerbos/README.md) | the application's discipline; policies versioned and tested as their own artifact | verdict and matched rule | commit for facts; policy propagation (the poll interval) for rules | policy files; a policy owner | one sidecar |
| OpenFGA | `turnstile_fga` | [`example_fga`](apps/example_fga/README.md) | the application's discipline, backed by the seam; the graph decides | the path (`Expand`) | commit, the relay pass, the engine write, and the check-cache TTL for facts; model publication for rules | a model file in a repository, published as an immutable model id; tuples the outbox keeps in step | a server and a datastore: two inventory items, one engine if the datastore shares the application's Postgres instance |


## Quickstart

The Nix flake carries the toolchain and every service, so the only thing to install is Nix. From the repository root:

```
nix develop
mix deps.get
mix test
```

`mix test` raises an ephemeral Postgres cluster on a unix socket under `tmp/` for the run, migrates it as the owner role, and removes it on exit. The dev services are untouched, so a suite and a database being worked on side by side cannot collide.

Then run one thin application's scenarios, in the same shell, to see the example decided by one adapter:

```
cd apps/example_rbac
mix test
```

Every scenario of `docs/reference.md` §3a is a test there, named by its id and the sentence that defines it. `apps/example_postgres` runs the same scenarios with the rules in migrations rather than in code, `apps/example_cerbos` with the rules in policy files a sidecar reads, and `apps/example_fga` with the rules in a model and the facts in a relationship graph. Each thin application's README has the translation table from the domain's words to its adapter's.

## Layout

An umbrella. `apps/turnstile` holds the port, the structs, the behaviours, the fact-mapping macro, the configuration struct, the conformance mechanisms, the test cluster, and the schema-dump task. `apps/turnstile_rbac`, `apps/turnstile_postgres`, `apps/turnstile_cerbos`, and `apps/turnstile_fga` are the adapters, `apps/turnstile_relay` is batched ordered delivery from a Postgres table, which the OpenFGA drain runs on, `apps/turnstile_credo` holds the Credo checks this repository adds, `apps/turnstile_dev` starts the Cerbos and OpenFGA binaries a run needs, `apps/example` is the example domain and its scenarios, and `apps/example_rbac`, `apps/example_postgres`, `apps/example_cerbos`, and `apps/example_fga` are the thin applications that bind an adapter to it.

## Working on it

Everything runs through the flake:

```
nix develop --command mix quality
```

The `quality` alias formats, compiles with warnings as errors, runs Credo strict, checks compile-time dependencies and cycles, audits dependencies, builds the docs, and runs the tests with coverage. `.github/workflows/ci.yml` runs the same alias across four test partitions, and one job per thin application that regenerates the committed schema dump and runs the scenarios.

## The documents

- `PLAN.md`: what the library is and why.
- `docs/reference.md`: the requirement groups, the rules of the example, the scenarios, the frozen contracts, the adapter comparison, and the pinned versions.
- `docs/testing.md`: the test environment, the tiers and their tags, and what CI runs.
- `docs/code.md`: the code conventions, the boundaries, and the `quality` alias.
- `docs/delivery.md`: how one piece of work runs from start to commit, and the gate each package passes.
- `docs/writing.md`: the prose rules every document here is held to.
- `docs/glossary-index.md`: every word that carries more than one meaning, and the one place each meaning lives.
