# Turnstile dev

The engine servers this repository's suites raise, and the test that holds the umbrella's source tree to its shape. Nothing here ships to Hex.

- `Turnstile.Dev.Cerbos`: one `cerbos server` per `mix test` run, and one owned by a single test where that test publishes a policy version or reads a decision log the run's sidecar must not see. It writes a configuration file naming the caller's policy directory, an audit log under `tmp/`, and a free port of the loopback interface.
- `Turnstile.Dev.Fga`: one `openfga run` per `mix test` run with the in-memory datastore, and one owned by a single test where that test needs a store the run's server must not see.

Both start the process under `MuonTrap.Daemon`, which kills it when the Erlang process that owns it dies and when the virtual machine exits, and both wait on the server's health endpoint before they answer, so a caller never asks a server that is not listening yet.

`StructureTest`, in this package's own suite, reads every `.ex` file under each package's `lib` and `test/support` and holds one rule over it: the file's path names a module the file defines, and every other module the file defines is named under that one. It reads the syntax tree rather than the compiled modules, so it needs no dependency on the packages it reads. `PLAN.md` §2 states the rule and the two dependency gates that shape it; the test names the one file that cannot follow it, with the reason.

`glossary.md` defines the words this package owns.

## Why the launchers are here

Starting an operating-system process takes `muontrap`, and a published adapter carries no dependency its own users have no use for. `turnstile_cerbos` and `turnstile_fga` take this package as `{:turnstile_dev, in_umbrella: true, only: :test}`, so nothing it holds can be called from a published package's `lib`, and Boundary checks that.

What the suites need besides a server stays in `turnstile_core`. The cluster and the sandbox setup are in its `lib`, since `mix turnstile.schema_dump` raises a cluster from a published package and an adapter outside this repository sets its sandbox up the same way. The repos, the neutral fixture, and the small adapters that reach a branch no shipped adapter reaches are in its `test/support`, compiled and never published.
