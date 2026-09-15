# Turnstile

Turnstile is the minimal port-and-adapters API an Elixir application needs to express its authorization for a FedRAMP Rev 5 Moderate target. An application asks one port whether a subject may perform an operation on an object; an adapter answers from roles in code, from Postgres row-level security, from a Cerbos sidecar, or from an OpenFGA store; a mediated Ecto repo refuses any read or write of a protected table that carries no decision, so nothing is accessed unlogged; and three telemetry events, decision, change, and access, carry what an audit record needs. `docs/requirements.md` lists the NIST lines this answers, and the conformance suite is what says an adapter answers them.

## The port

```elixir
# one object: the decision the seam accepts
with {:ok, decision} <- Turnstile.authorize(subject, :read, {:document, id}) do
  Repo.get(Document, id, turnstile: decision)
end

# a yes or no, for a branch that does not reach the repo
Turnstile.check(subject, :approve, {:proposal, id})

# a whole type: a rule the query carries, which can only narrow
{rule, decision} = Turnstile.scope(subject, :read, :document)
Repo.all(from(d in Document, where: ^rule), turnstile: decision)

# who can do what today, asked by a reviewer
Turnstile.review(reviewer, subjects, :read, :document)
```

A subject is `{kind, id}`, an object `{type, id}`, and the options carry the caller's environment facts and an operation id that every event of one operation shares.

## The four adapters

One port, four mechanisms. Each is a package, and each has a thin application that binds it to the same example domain and whose README says what each rule of that domain is enforced by.

| Adapter | Package | Example | Rules live in | Revocation latency components | Boundary cost |
|---|---|---|---|---|---|
| Roles in code | `turnstile_rbac` | [`example_rbac`](apps/example_rbac/README.md) | Elixir modules; a deploy is a policy version | commit | none |
| Postgres row-level security | `turnstile_postgres` | [`example_postgres`](apps/example_postgres/README.md) | migrations; a migration is a policy version | commit | none new |
| Cerbos | `turnstile_cerbos` | [`example_cerbos`](apps/example_cerbos/README.md) | policy files with an owner of their own | commit for facts; policy propagation for rules | one sidecar |
| OpenFGA | `turnstile_fga` | [`example_fga`](apps/example_fga/README.md) | a model published as an immutable id; tuples an outbox keeps in step | commit, a relay pass, the engine write, and the check-cache TTL | a server and a datastore |

## Quickstart

The Nix flake carries the toolchain and every service, so the one thing to install is Nix. From the repository root:

```
nix develop
mix deps.get
mix test
```

`mix test` raises an ephemeral Postgres cluster on a unix socket under `tmp/` for the run and removes it on exit. Then run one thin application's scenarios to see the example decided by one adapter:

```
cd apps/example_rbac
mix test
```

Every scenario of `docs/example.md` is a test there, named by its id and sentence. The other three thin applications run the same scenarios with the rules in migrations, in policy files, and in a relationship graph.

## Layout

An umbrella. `apps/turnstile` is the port, the seam, the events, and the conformance suites. `apps/turnstile_rbac`, `apps/turnstile_postgres`, `apps/turnstile_cerbos`, and `apps/turnstile_fga` are the adapters. `apps/turnstile_credo` holds the two static checks. `apps/turnstile_dev` holds the test cluster and the engine launchers and is not published. `apps/example` is the domain and its scenarios, and `apps/example_rbac`, `apps/example_postgres`, `apps/example_cerbos`, and `apps/example_fga` bind it to one adapter each.

Inside every package the same places mean the same thing: the root of `lib/` is the interface, `domain/` is what the package knows, `application/` is its use cases, and `infrastructure/` is what touches the world or speaks another system's language. `docs/design.md` §6 has the table.

## Working on it

```
nix develop --command mix quality
```

`quality` audits dependencies, formats, compiles with warnings as errors, runs Credo strict, checks compile-time dependencies and cycles, builds the docs, and runs every suite with coverage. `docs/contributing.md` has the rest.

## The documents

- `docs/design.md`: what Turnstile is, the port, the seam, the events, the packages, and the words.
- `docs/requirements.md`: the NIST lines, one row per applicable control, and what answers each.
- `docs/conformance.md`: the laws every adapter passes and the guarantees every repo passes.
- `docs/events.md`: the payload of each event and the OCSF mapping the example shows.
- `docs/example.md`: the CUI domain, its thirteen rules, and the scenario table.
- `docs/contributing.md`: toolchain pins, the test environment, code and prose conventions, and the gate.
