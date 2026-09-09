# Turnstile

Turnstile is an Elixir authorization library built for FedRAMP Moderate assessment-readiness. An application asks one port, the `Turnstile` module, whether a subject may perform an operation on an object; an adapter answers from roles in code, from Postgres row-level security, from a Cerbos sidecar, or from an OpenFGA store; a mediated Ecto Repo refuses any query that carries no decision; and a ledger records every fact change so that access can be reviewed on any date and every recorded decision can be replayed.

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

One port, four mechanisms. Each is a package of its own, and each has a thin application that binds it to the same example domain and declares what every rule of that domain is enforced by. `docs/reference.md` §4 carries this table and the notes per adapter.

| Adapter | Package | Example application | Enforcement | Explains | Revocation latency components | Rules live in | Boundary cost |
|---|---|---|---|---|---|---|---|
| RBAC in code | `turnstile_rbac` | [`example_rbac`](apps/example_rbac/README.md) | the application's discipline, backed by the seam | the clause | commit | Elixir modules; a deploy is a policy version | none |
| Postgres row-level security | `turnstile_postgres` | [`example_postgres`](apps/example_postgres/README.md) | the database; write gates need no application code (a printed note, not a rule) | verdict only | commit | migrations; a migration is a policy version | none new |
| Cerbos | `turnstile_cerbos` | `example_cerbos` | the application's discipline; policies versioned and tested as their own artifact | verdict and matched rule | commit for facts; policy propagation (the poll interval) for rules | policy files; a policy owner | one sidecar |
| OpenFGA | `turnstile_fga` | `example_fga` | the application's discipline, backed by the seam; the graph decides | the path (`Expand`) | commit, projector drain, engine write, check-cache TTL for facts; model publication for rules | a model file in a repository, published as an immutable model id; tuples projected from the ledger | a server and a datastore: two inventory items, one engine if the datastore shares the application's Postgres instance |

`example_cerbos` and `example_fga` carry no link yet: they arrive with their adapter packages, as `docs/delivery.md` lists them.

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
EXAMPLE_LEDGER=ecto mix test
```

Every scenario of `docs/reference.md` §3a is a test there, named by its id and the sentence that defines it. The same file runs with `EXAMPLE_LEDGER=none`, which excludes the scenarios a ledger answers, and `apps/example_postgres` runs the same scenarios with the rules in migrations rather than in code. Each thin application's README has the translation table from the domain's words to its adapter's, and `apps/example_rbac/README.md` has the review of a past date, which wants a database that outlives one test run.

## Layout

An umbrella. `apps/turnstile_core` holds the port, the structs, the behaviours, the fact-mapping macro, the configuration struct, the conformance mechanisms, and the test cluster. `apps/turnstile_ledger` holds the Ecto ledger, its migration helpers, reconcile, replay, the review table, and the schema-dump task. `apps/turnstile_rbac` and `apps/turnstile_postgres` are the first two adapters, `apps/turnstile_example` is the example domain and its scenarios, and `apps/example_rbac` and `apps/example_postgres` are the thin applications that bind an adapter to it. The remaining adapter packages and thin applications arrive stage by stage, as `docs/delivery.md` lists them.

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
- `docs/delivery.md`: the stages, in order, and the gate each one passes.
- `docs/writing.md`: the prose rules every document here is held to.
- `docs/glossary-index.md`: every word that carries more than one meaning, and the one place each meaning lives.
