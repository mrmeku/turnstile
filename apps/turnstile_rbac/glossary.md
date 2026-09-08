# RBAC in code glossary

The words `turnstile_rbac` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Policy module | A module that used `Turnstile.Code.Policy`: the role table and, per protected schema, the clauses of its rule |
| Role table | The rows `role name, permissions` declare: data the version carries by value |
| Clause | One part of a protected schema's rule: a grant or a predicate, named so a reason and an explanation can cite it |
| Grant | A clause that holds a role on a row through a relationship schema: the row's `on` column is among the object columns of the relationship rows that name the subject with a permitting role, or among the keys of the hop rows that reach them |
| Hop | One schema a grant crosses on its way from the relationship to the protected row: the column of it the inner set matches, its primary key as the next set, and an optional filter over its rows |
| Predicate | A clause that is a named function of the subject and the environment, returning a `dynamic` over the row or a boolean; every predicate that applies to the operation must hold |
| Rule | A protected schema's clauses built for one subject and operation: any grant and every predicate, as one `dynamic` over subqueries |
| Binding | The policy module and the mediated repo the rules read through, bound once at boot or overridden per process |
| Content hash | The digest of the policy module and every module a predicate or a hop filter lives in; the default version identifier |
| Publish | Append the policy version at boot when the ledger's latest names an older one or none; telemetry alone in ledger mode none |
| Coverage | The walk of every rule's `dynamic`, subqueries included, that fails on a column no declaration names |
| Finding | One undeclared read: a schema and a column, or a fragment's text |
