# Turnstile core

The port and everything that is the same for every adapter.

- `Turnstile.Adapter`: the behaviour an adapter implements: `authorize`, `check`, `batch`, `scope`, and the optional `explain` and `around_query`, plus `requires_ledger/0`, `scope_cap/0`, and an options schema.
- The values that cross the port: `Turnstile.Subject`, `Turnstile.Object`, `Turnstile.Environment`, `Turnstile.Answer`, `Turnstile.Scope`, `Turnstile.Explanation`, `Turnstile.Decision`, `Turnstile.Reason`, `Turnstile.PolicyVersion`, `Turnstile.FactEvent`, `Turnstile.Exemption`, and the errors under `Turnstile.Error`.
- `Turnstile.Ledger` and `Turnstile.Projection`: the behaviours behind the ledger and behind an adapter's state; `Turnstile.Ledger.Memory` and `Turnstile.Adapter.Fake` are the in-memory implementations tests bind.
- `use Turnstile.Schema`: the fact mapping, column by column, from an application's schemas to the four fact kinds.
- `use Turnstile.Repo`: the seam. `Turnstile.Repo.Surface` lists every `Ecto.Repo` function in one of four buckets; the overrides hand each query, write, and raw call to `Turnstile.Repo.Seam` with the `turnstile:` option, a decision or an exemption, resolved into a `Turnstile.Repo.Mediation`. A call on a protected schema that carries neither raises `Turnstile.Error.Unmediated` before any SQL; a write to a fact schema re-reads the row under the ledger's lock and appends its fact events in the same transaction.
- `Turnstile.Conformance.RepoCase`: the test that diffs the surface against a repo's exports and calls every non-plumbing function on a protected schema without a decision.
- `Turnstile.Credo.NoRawSQL` and `Turnstile.Credo.UnmediatedRepo`: the checks that keep raw SQL and unmediated repos out of `lib`.
- `Turnstile.Config`: the one configuration struct, validated once at boot; `Turnstile.Test.with_config/1,2` overrides it per process in tests.
- `Turnstile.Conformance`: the scenario table, the `scenario` macro, and the adapter case template that every adapter, in this repository or outside it, proves itself against.
- `Turnstile.Test.Cluster`: the ephemeral Postgres cluster `mix test` starts.

`glossary.md` defines the words this package owns. Core's `lib` depends on `ecto` and `nimble_options`; `ecto_sql` and `postgrex` serve its own tests only, and Boundary checks that no call from `lib` reaches them.
