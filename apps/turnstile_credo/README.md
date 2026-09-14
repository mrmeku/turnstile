# Turnstile Credo checks

Two static checks that find the two ways an application's queries leave the seam. They read source text and answer Credo issues, so nothing here runs in a system that is serving requests.

- `Turnstile.Credo.NoRawSQL`: flags `Ecto.Adapters.SQL.query/2,3,4`, its bang and many forms, and any `Postgrex` call. Each reaches the database around the repo that checks decisions, so nothing checks it. A module the seam itself rests on, an outbox's writer or a test cluster's bootstrap, is named in the check's `allow` parameter as a module-name prefix.
- `Turnstile.Credo.UnmediatedRepo`: flags a module that `use Ecto.Repo` without `use Turnstile.Repo` beneath it. Such a repo answers every query with no decision checked.

Both are advisory: a check reads what a file says, not what a call does at run time, and neither is what enforces a decision. What enforces it is the seam, and `Turnstile.Conformance.RepoCase` is what proves the seam covers the surface.

## Using them

Add the package to an application's `:dev` and `:test` dependencies, and name the checks in `.credo.exs`:

```elixir
{Turnstile.Credo.NoRawSQL,
 [
   files: %{included: ["lib/", "apps/*/lib/"]},
   allow: ["MyApp.Outbox"]
 ]},
{Turnstile.Credo.UnmediatedRepo, []}
```

`glossary.md` defines the words this package owns. The package depends on `credo` and on nothing else, this repository's packages among them, which is why it is a package rather than a module of the contract.
