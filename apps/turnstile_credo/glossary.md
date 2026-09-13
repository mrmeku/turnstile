# Turnstile Credo glossary

The words `turnstile_credo` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Check | A Credo check: a module that reads a source file and answers issues |
| Raw SQL | A query that reaches the database around a repo that `use Turnstile.Repo`, so no decision is checked for it |
| Unmediated repo | A module that `use Ecto.Repo` without `use Turnstile.Repo` beneath it |
| Allow | The `NoRawSQL` parameter naming the module prefixes whose raw SQL is the seam's own |
| Advisory | A check that reports and does not enforce: what enforces a decision is the seam |
