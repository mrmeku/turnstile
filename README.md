# Turnstile

Turnstile is an Elixir authorization library built for FedRAMP Moderate assessment-readiness. An application asks one port, the `Turnstile` module, whether a subject may perform an operation on an object; an adapter answers from roles in code, from Postgres row-level security, from a Cerbos sidecar, or from an OpenFGA store; a mediated Ecto Repo refuses any query that carries no decision; and a ledger records every fact change so that access can be reviewed on any date and every recorded decision can be replayed.

`PLAN.md` states what the library is and why. The documents under `docs/` are the working rules: `docs/reference.md` holds the requirements, the rules, the scenarios, and the frozen contracts; `docs/testing.md` the test environment; `docs/code.md` the code conventions; `docs/delivery.md` the stages and their gates; `docs/writing.md` the prose rules; `docs/glossary-index.md` the words that carry more than one meaning.

## Layout

An umbrella. `apps/turnstile_core` holds the port, the structs, the behaviours, the fact-mapping macro, the configuration struct, the conformance mechanisms, and the test cluster. `apps/turnstile_ledger` holds the Ecto ledger's migration helpers and the schema-dump task. The adapter packages and the thin example applications arrive stage by stage, as `docs/delivery.md` lists them.

## Working on it

Everything runs through the Nix flake:

```
nix develop --command mix quality
```

The `quality` alias formats, compiles with warnings as errors, runs Credo strict, checks compile-time dependencies and cycles, audits dependencies, builds the docs, and runs the tests with coverage. `mix test` starts an ephemeral Postgres cluster on a unix socket under `tmp/` for the run and removes it on exit.
