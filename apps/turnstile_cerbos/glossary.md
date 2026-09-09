# Cerbos glossary

The words `turnstile_cerbos` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Sidecar | The Cerbos server running beside the application, reading a policy directory and answering over HTTP and JSON at the address the configuration entry names |
| Policy directory | The directory of policy files the sidecar reads and reloads when it changes, named by the binding |
| Commit | The commit of the policy repository the directory is at, which is the policy version every decision under the binding names |
| Declaration | The module that used `Turnstile.Cerbos.Attributes`: a block per subject kind and per object type, and the attributes inside them |
| Attribute | One name the policies read, mapped to a column of the kind's schema or to a subquery of the subject |
| Column attribute | An attribute whose value is what the row holds, which a query plan compiles to a comparison on that column |
| Subquery attribute | An attribute whose value comes from a function of the subject returning a query that selects `%{id: ..., value: ...}` with the value as text, which a query plan compiles to membership in the ids it selects |
| Principal | The subject as the sidecar is told it: the id, a role per subject kind, and the declared attributes of that kind |
| Resource | One object as the sidecar is told it: the object type as its kind, the id, and the declared attributes of that type |
| Query plan | The filter the sidecar answers a plan request with, over the resource attributes it could not resolve |
| Plan | The compilation of that filter into a `dynamic` over the object type's rows |
| Fallback | A plan the compiler cannot express: `scope` fails, `[:turnstile, :cerbos, :scope_fallback]` is emitted, and the caller asks per row |
| Matched policy | The policy the sidecar reports it evaluated for a resource and an action, carried as the rule of a reason where the sidecar named one |
| Content | The policy files as one text, each preceded by its path, which the version carries by value under the cap |
| Publish | Append the policy version at boot when the ledger's latest for this adapter names an older commit or none; telemetry alone in ledger mode none |
| Propagation | The interval from writing policy text into the directory to the first answer that reflects it, this adapter's `policy_propagation` component of revocation latency |
| Decision log | The file the sidecar writes one JSON object per decision to, whose path the binding names |
| Line | One question and answer out of that file: who asked, the operation, the object, the verdict, and the attributes as they were sent |
| Reconciliation | Reading the decision log and the port's records of the same window and reporting every difference between them |
| Finding | One difference: a logged decision no record matches, a record no line carries, or a pair that agree on the question and disagree on the answer |
| Replay | A policy version written into a directory of its own for a sidecar the caller raised and throws away, and a stored decision asked again under it from the attributes the record carries |
| Coverage | The walk of the compiled query, subqueries included, that fails on a column no declaration names |
