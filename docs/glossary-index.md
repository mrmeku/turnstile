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
| Table | The fake adapter's rule table, an `Agent` per test | `apps/turnstile_core/glossary.md` |
| Table | A Postgres table, protected by the seam or truncated between committed tests | `docs/reference.md` §6, `docs/testing.md` §3 |
| Fold | `Turnstile.Ledger.Fold`: the facts a list of events leaves | `apps/turnstile_core/glossary.md` |
| Fold | The fold-then-replay property of Tier 1 | `docs/testing.md` §6 |
| Rule | A protected schema's clauses built for one subject and operation, as one `dynamic` | `apps/turnstile_rbac/glossary.md` |
| Rule | A rule of the example, C1 to C13, with its capability level | `docs/reference.md` §3 |
| Grant | A clause of a policy module that holds a role on a row through a relationship schema | `apps/turnstile_rbac/glossary.md` |
| Grant | The fixture's write of a membership, and the grant steps the properties generate | `apps/turnstile_core/test/support`, `docs/testing.md` §6 |
| Predicate | A clause of a policy module: a named function returning a `dynamic` or a boolean | `apps/turnstile_rbac/glossary.md` |
| Predicate | A Postgres row-level security policy's `USING` expression | `turnstile_postgres` glossary, from S6 |
| Binding | The policy module and repo `Turnstile.Code` reads through | `apps/turnstile_rbac/glossary.md` |
| Binding | An Ecto query binding, the `[row]` of a `dynamic` | Ecto's own documentation |
| Marking | A portion's or a document's categories, controls, and releasable-to list | `apps/turnstile_example/glossary.md` |
| Marking | The CUI marking of 32 CFR Part 2002, the banner and portion marks on a page | `docs/reference.md` §2 |
| Control | A dissemination control of the CUI Registry, a test on the subject | `apps/turnstile_example/glossary.md` |
| Control | A NIST SP 800-53 control, named by a scenario's `control:` tag | `docs/reference.md` §1 |
| Fixture | The example's world every scenario starts from | `apps/turnstile_example/glossary.md` |
| Fixture | The neutral fixture the conformance suite inserts | `apps/turnstile_core/glossary.md` |
| Override | The audited privileged read of C10 | `apps/turnstile_example/glossary.md` |
| Override | `Turnstile.Code.Binding.override/1,2`, a per-process binding for tests | `apps/turnstile_rbac/glossary.md` |
