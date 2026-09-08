# Glossary index

Every word that carries more than one meaning in this repository, and the one place each meaning lives. A package's glossary defines the words it owns; this index only points. Started at S1; each stage adds the words its package introduces.

| Word | Meaning | Where it lives |
|---|---|---|
| Scope | The port operation that narrows a query, and the `%Turnstile.Scope{}` it returns | `apps/turnstile_core/glossary.md` |
| Scope | A Postgres row-level security policy's reach over a table | `turnstile_postgres` glossary, from S6 |
| Version | A policy version: an artifact an adapter decides under, named in every decision | `apps/turnstile_core/glossary.md` |
| Version | A pinned dependency release in `docs/reference.md` §12 | `docs/reference.md` |
| Check | The port operation `check/4`: a yes or no without a decision record | `apps/turnstile_core/glossary.md` |
| Check | A Credo check, or OpenFGA's `Check` request | `docs/code.md` §5; `turnstile_fga` glossary, from S9 |
| Position | A ledger position: the index of a fact event, taken from the counter row | `turnstile_ledger` glossary |
| Position | The head position and the applied position a decision carries | `apps/turnstile_core/glossary.md` |
| Review | `mix turnstile.review` and the port's `review`: who can do what on a date | `apps/turnstile_core/glossary.md` |
| Review | Access review, the AC-2 activity the scenarios `rvw-01` to `rvw-04` cover | `docs/reference.md` §1 |
| Record | An audit record, the AU-3 shape | `apps/turnstile_core/glossary.md` |
| Record | A capability record: a rule's level with the enforcing component and a note | `apps/turnstile_core/glossary.md` |
| Declaration | A capability declaration in a thin app | `apps/turnstile_core/glossary.md` |
| Declaration | A fact-mapping declaration, `use Turnstile.Schema` | `apps/turnstile_core/glossary.md` |
| Owner | The owner role, `turnstile_owner`, and an owner-role repo | `docs/testing.md` §3, `docs/reference.md` §6 |
| Owner | The project's owner, who answers questions | `CLAUDE.md` |
| Sandbox | The Ecto SQL sandbox that wraps a test in a transaction | `docs/testing.md` §3 |
| Sandbox | The sandboxed database, `turnstile_test`, as against the committed one | `docs/testing.md` §3 |
| Caller | The module that called the Repo, as the seam reads it from the stack | `apps/turnstile_core/glossary.md` |
| Caller | The process that called `Turnstile.Test.with_config/1,2`, followed through `$callers` | `apps/turnstile_core/glossary.md` |
