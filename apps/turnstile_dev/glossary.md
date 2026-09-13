# Turnstile dev glossary

The words `turnstile_dev` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Launcher | The module that starts one engine's server for a suite and stops it with the run |
| Shared server | One server for the whole run, started from `test_helper.exs` and stopped after the suite |
| Owned server | A server one test starts through the test supervisor, for a test that publishes or reads what the run's server must not see |
| Health endpoint | The path a launcher polls before it answers, so a caller never asks a server that is not listening yet |
| Structure rule | The one rule `StructureTest` holds every compiled source file to: its path names a module it defines, and its other modules are named under that one |
