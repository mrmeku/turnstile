# Contributing

*How the repository is built, tested, written, and delivered. The toolchain pins and where each was verified, the test environment, the code conventions, the prose rules, and the gate every stage ends with.*

## 1. Toolchain

Nix pins the toolchain and every service; a contributor installs Nix and the flake does the rest. No Docker. `direnv` with `use flake` makes entering the directory entering the environment, and CI runs `nix develop --command mix quality`, so dev and CI are the same closure.

**Pins**, verified 2026-09-07.

| Component | Version | Nix expression | Where verified |
|---|---|---|---|
| nixpkgs | `nixos-unstable`, head `c043004d…` (2026-09-05) | the flake's locked input | stable 26.05 has openfga 1.14.2, so unstable is the branch matching every pin at once |
| Erlang/OTP | 29.0.6 | `beam.packages.erlang_29` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/erlang/29.nix, same on `nixos-unstable` |
| Elixir | 1.20.4 | `beam.packages.erlang_29.elixir_1_20` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/development/interpreters/elixir/1.20.nix (minimum OTP 27, maximum 29) |
| PostgreSQL | 18.6 | `postgresql_18`, written explicitly, never the bare `postgresql` alias | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/servers/sql/postgresql/18.nix; the alias is 18 on unstable and 17 on both stable branches |
| OpenFGA | 1.19.0 | `pkgs.openfga` | https://raw.githubusercontent.com/NixOS/nixpkgs/master/pkgs/by-name/op/openfga/package.nix; release https://api.github.com/repos/openfga/openfga/releases/latest (published 2026-08-25) |
| Cerbos | 0.55.0 | a `stdenvNoCC` derivation that `fetchurl`s `cerbos_0.55.0_<Linux\|Darwin>_<x86_64\|arm64>.tar.gz` per system with hashes in the flake | absent from nixpkgs on every branch (https://github.com/NixOS/nixpkgs/issues/290460); release https://api.github.com/repos/cerbos/cerbos/releases/latest (published 2026-08-13); the tag has `v`, the filename does not |
| services-flake | active, last commit 2026-08-18 | the flake's input; `postgres` service, Cerbos and OpenFGA as process-compose processes | https://github.com/juspay/services-flake; no cerbos or openfga service module |

**Hex pins**, verified against https://hex.pm/api/packages/<name> on 2026-09-07; `mix.lock` is the pin.

| Package | Version | Note |
|---|---|---|
| `nimble_options` | 1.1.1 | |
| `stream_data` | 1.4.0 | a runtime dependency of `turnstile`, because the conformance generators are the product an adopter runs |
| `boundary` | 0.10.4 | two years without a release; compiles and reports on Elixir 1.20 |
| `styler` | 1.12.2 | |
| `muontrap` | 2.0.0 | a new major; the `MuonTrap.Daemon` API the launchers use is checked against its 2.0 changelog |

On Darwin the Cerbos binary reaches the machine as a tarball unpacked into the Nix store, so no quarantine attribute is attached and Gatekeeper does not prompt; a comment beside the derivation in `flake.nix` says so. In the shell the flake gives, `cerbos --version` prints 0.55.0 and `openfga version` prints 1.19.0. `nix run .#services` brings up Postgres, Cerbos, and OpenFGA on local ports for running a thin application by hand; `mix test` never touches them.

## 2. The test environment

**Every test owns its state**: its own connection, clock, configuration, Cerbos when it changes policies, OpenFGA store, operation ids, and processes. `async: true` is the default, and `async: false` is a tagged exception with its reason in the tag.

**The ephemeral cluster.** `test_helper.exs` in every app calls `Turnstile.Dev.Cluster.start/1`, which runs `initdb` into `tmp/pg-<random>/` with `--auth=trust` and starts Postgres on a unix socket with no TCP port and `fsync=off`; creates two roles, `turnstile_owner`, which owns the tables and runs migrations, and `turnstile_app`, which does not and carries `NOBYPASSRLS`; creates `turnstile_test` and `turnstile_committed`; runs the migrations the caller names as the owner, through the `migrate:` function the caller passes; configures the test repos at boot, the one place `Application.put_env` is allowed; and registers `ExUnit.after_suite/1` and `System.at_exit/1` to stop every cluster and remove its directory. Startup is about a second. The socket directory is random, so `mix test --partitions N` runs N clusters side by side.

Inside the run, the SQL sandbox in `:manual` mode gives each test a connection wrapped in a transaction; `Turnstile.Dev.Sandbox.setup/2` is what every case template's `setup` calls. A test tagged `:committed` gets no sandbox: it runs real commits on the committed database and truncates through the owner-role repo in `setup` and `on_exit`. Session settings the Postgres adapter binds inside `around_query/3` are transaction-scoped, so they cannot leak between tests.

**Cerbos and OpenFGA.** The launchers live in `turnstile_dev`, which is never published, because starting an operating-system process takes `muontrap` and an adapter package carries no dependency its users do not need. `Turnstile.Dev.Cerbos.start_shared/1` starts one `cerbos server` for the run under `MuonTrap.Daemon` on a free loopback port, serving the calling app's policy directory; `example_cerbos` serves a copy under `tmp/` because a scenario that publishes a rule change writes a policy file into the directory the sidecar watches. `Turnstile.Dev.Fga.start_shared/1` starts one `openfga run --datastore-engine memory`; isolation inside it is a store per test. A test that publishes a version or reconciles against out-of-band writes starts its own instance with `start_supervised` and a temp directory, about a hundred milliseconds, and is still async. A test that needs no server runs against `Turnstile.Fga.Client.Fake`, an `Agent` in `turnstile_fga`'s test support.

**The async patterns.**

| Shared thing | Pattern |
|---|---|
| The clock | `Turnstile.Test.Clock.set/1` installs a closure over one moment for the rest of the calling process; the override travels through `$callers` |
| Configuration | `Turnstile.Test.with_config/1` for the rest of the process, `with_config/2` around a function; `Turnstile.Config.resolve/0` checks `self()` and the `$callers` chain. `Application.put_env` inside a test is banned |
| Telemetry handlers | `Turnstile.Test.queries/2` and `changes/1` attach for one function and drop events from other processes; a decision assertion routes events to itself with `:telemetry_test.attach_event_handlers/2` and filters by the operation id it passed |
| The fake adapter | `Turnstile.Test.Fake`, an `Agent` per test via `start_supervised`, bound through the override; it returns values of the real types and never raises in their place |
| The OpenFGA store | A store per test, the model published in `setup`, its id in the override |
| The relay's runner | Startable unnamed with the repo, the job, and the clock injected; tests drive `drain_once/1` and never leave a runner ticking. `Turnstile.Test.settle/0` settles the configured adapter where it has state of its own and answers `:none` otherwise |
| Time | No `Process.sleep/1` outside `Turnstile.Test.poll/2`, a deadline loop used for latency measurement and for waiting on external processes |

**What proves what.** Conformance suites (`AdapterCase`, `RepoCase`, and the `OutboxCase` and `TupleMappingCase` of `turnstile_fga`) prove that a module touching the world behaves as every other of its kind. Properties prove a decision is right for inputs nobody thought of, over modules under `domain/` that need no database. Scenarios prove the example obeys its own rules under every binding. Shape tests prove the work is the size it should be, by counting queries and events rather than timing them. `docs/conformance.md` has the first; `docs/example.md` §4 has the third.

**The count test.** `use Example.Scenarios` ends by defining one more test: the scenario ids defined across the module are the table's ids, all of them and no others. No binding declares a scenario unsupported, so a green run answered every row.

**The structure test**, in `turnstile_dev`, reads every `.ex` under each package's `lib` and `test/support` from the syntax tree and holds it to `docs/design.md` §6: the path names a module the file defines, every other module in the file is named under it, a module under `domain/` calls nothing that touches the world and names no module under `application/` or `infrastructure/`, a module under `infrastructure/` names no module under `application/`, and in a published package the modules under the three places carry `@moduledoc false`.

**Committed outputs.** The one output compared against a file is the schema dump: `mix turnstile.schema_dump` in a thin application raises a cluster, runs its migrations as the owner, writes `pg_dump --schema-only` into `priv/schema/<adapter>.sql`, and CI's `git diff --exit-code priv/schema/` is the assertion. The Postgres dump is where the row-level security policies are legible as SQL.

## 3. Code

**Write inferable code.** Elixir 1.20 infers the types of whole function bodies, guards, and clauses across applications and reports dead clauses and verified bugs; it avoids false positives, so every type warning is a bug and `warnings_as_errors: true` treats it as one. `@spec` and `@type` are documentation, not checker input, and Credo keeps them present. Leave the checker evidence: structs over bare maps, atom unions over strings, generated clauses over attribute lookups, fakes that return real types.

**Records are structs.** No bare map crosses a function boundary inside the library as an ad hoc struct. Every struct has `@enforce_keys` for every field without a meaningful default, `defstruct`, `@type t` with every field typed, and `@moduledoc`. On a struct, `Map.put/3`, `Map.merge/2`, `Map.update/4`, `Map.delete/2`, and `Access` are banned; update with `%S{s | field: v}`. Three things stay maps: the environment, `Answer.meta`, and a telemetry payload, each built at exactly one edge. Options are `NimbleOptions` schemas, never `opts[:foo]` without one.

**The knobs**, all on, in every app: `elixir: "~> 1.20.4"`, `elixirc_options: [warnings_as_errors: true, infer_signatures: true, no_warn_undefined: []]`, `use Boundary` with explicit `deps:` and `exports:` in every root module, `@impl true` on every callback, `mix format --check-formatted` with `plugins: [Styler]`, `mix credo --strict --all` with every check on and each disabled one carrying a comment, coverage thresholds of 90 percent per application and 100 percent over `domain/` under `TURNSTILE_DOMAIN_COVERAGE`. Dialyzer and runtime type-check libraries are off on purpose: the compiler's checker has the sound half of what they offered.

Credo checks off by default and on here: `Readability.Specs`, `StrictModuleLayout`, `ImplTrue`, `WithSingleClause`, `Refactor.WithClauses`, `Apply`, `ABCSize`, `CyclomaticComplexity`, `Nesting` at strict thresholds, `Warning.UnsafeToAtom`, `MapGetUnsafePass`, `Design.AliasUsage`, `TagTODO` and `TagFIXME` as failures. Shipped in `turnstile_credo`: `Turnstile.Credo.NoRawSQL` and `Turnstile.Credo.UnmediatedRepo`, which excepts the owner-role repo.

**Idioms.**

- Module layout in Styler's order: `@moduledoc`, `@behaviour`, `use`, `import`, `alias`, `require`, attributes, `@enforce_keys` and `defstruct`, `@type`s, `@callback`s, public functions, private functions. One module, one concept; no `Helpers` or `Utils`.
- Every pluggable thing is a `@behaviour`; surfaces are enumerated with the behaviour's `behaviour_info/1`; optional callbacks are answered at runtime with `function_exported?/3`, so one build serves every adapter. No protocols.
- Declarations are generated clauses: `use Turnstile.Schema` accumulates at compile time and a `@before_compile` writes `__turnstile__/1` one clause per question; an adapter's `scope_cap/0` and `settle/0` are the same.
- Errors are values: `{:error, %Turnstile.Error{}}` with a reason atom. A programmer error raises. The port never raises on the request path; the seam's refusal raises, because an unmediated call is a programmer error. No `{:error, :atom}`, no strings, no `nil` for not found.
- Predicates end in `?` and return exactly `true` or `false`. `String.to_atom/1` is banned; `Ecto.Enum` for atom-valued fields. `nil` in a struct only where absence is meaning, and every consumer branches on it.
- `with` for a chain of results, every `else` clause naming its shape; no `try/rescue` for control flow.
- `apply/3`, `__info__/1`, and `Code.*` are confined to the conformance templates and allowlisted in Credo by module. The seam's overrides are `@before_compile` with `defoverridable` and `super`. Public macros are `use Turnstile.Repo`, `use Turnstile.Schema` and its declarations, the case templates, and `scenario`.
- Library code owns one long-lived process, the relay's runner, startable unnamed. The process dictionary is touched in the seam's mediation entry, the dynamic-repo entry, and the test configuration resolver, nowhere else.
- Ecto: `@primary_key` and field types explicit; changesets cast at the edge; the repo only through the seam or the owner-role repo. The `dynamic` that `scope` returns is opaque to the checker and is covered by the scope-fidelity law instead.
- `@doc` on every public function, `@typedoc` on every public type, `@doc false` for what a macro needs public; a doctest where an example is cheap and true. Comments explain why, never what.
- Naming: `Turnstile.` for library modules, `Example.` and `ExampleRbac.`, `ExamplePostgres.`, `ExampleCerbos.`, `ExampleFga.` for the example. A struct's module is a noun, a behaviour's a role. "Adapter", never "provider". Test names are law ids and sentences from `docs/conformance.md`, or scenario ids and sentences from `docs/example.md`.

**Placement** is `docs/design.md` §6 and `CLAUDE.md`: ask the placement question before adding a module, and put it in the place the answer names.

## 4. Prose

The rules every document here is held to. Sources: the Google developer documentation style guide for tone and mechanics, the Microsoft Writing Style Guide for register, Elixir's *Writing documentation* for `@moduledoc` and `@doc`, *Art of README* for what a README is, and Minto's *The Pyramid Principle* for the shape of an explanation.

Two registers. Prose that explains (`docs/design.md`, each package README) is informative: it states the problem before the mechanism, names the idea after showing it, and says why the alternative was not taken. Code and reference (modules, tables, callback specs, `docs/conformance.md`, `docs/events.md`) is terse: what a thing is and when to use it, then stop. A reader should be able to tell which register they are in from the first line.

- Active voice, present tense. Second person in how-to; impersonal in reference.
- Sentence-case headings.
- Define before use; one word per concept: "adapter" never "provider", and "subject", "object", "operation", "environment" from NIST SP 800-162.
- One idea per paragraph; the consequence of that idea may share it.
- Banned words: *simply, just, obviously, easy, easily, of course, basically, note that, in order to*. They tell a struggling reader the problem is them, or add nothing.
- No exclamation marks. No em-dashes: a comma, a colon, or a new sentence does the work.
- A concept that belongs to someone else gets two sentences in our words and a link, never a section. Show an idiom in use before naming it.
- `@moduledoc`: the first sentence stands alone in a module list; then when to use the module and what it is not. `@doc`: what the function returns or does, in the third person, then arguments, then an example.
- The README summarizes and is the source of nothing. A thin application's README is a how-to: what the binding costs, in the directory's order, then the rule-to-mechanism table, then the translation table. An adapter package's README is mechanism per rule shape, what it declares, and its measured latency; no sentence in it tells the application what it may do.

The gate is the grep in `CLAUDE.md`, run over every changed document; it prints `exit=1`. This file is the one exception, because it is where the banned words are listed.

## 5. Delivery

**How a stage runs.**

1. Read `CLAUDE.md` and the files it lists, then whatever the work needs. Read nothing else.
2. Work on `main`, no worktree, no branch. Stages are sequential.
3. Every command runs inside `nix develop --command`, from the directory the gate names. Green means exit 0 with warnings as errors.
4. Run the gate of every package the work touched, then the root gate.
5. Run the prose gate over every document changed.
6. Commit, unsigned, one idea per commit: `git -c commit.gpgsign=false commit`. The last commit message quotes every gate command and its output verbatim, then records a version pinned or re-verified and where, a call the plan left open and which way it went, and anything the next stage needs that no document says. Push after every commit.

A gate that fails is not worked around: report what failed and stop.

**The root gate.** At the root, `mix quality` is `hex.audit` first, because Hex requires it before any task that loads the application, then `format --check-formatted`, `compile --force --warnings-as-errors --all-warnings`, `credo --strict --all`, `xref graph --label compile-connected --fail-above 0`, `xref graph --format cycles --fail-above 0`, `deps.unlock --check-unused`, `deps.audit` with the one acknowledged advisory named by id in `mix.exs` beside its reason, `docs --warnings-as-errors`, and the test step, which runs each app's suite in an operating-system process of its own, because the thin applications bind the same example modules and one VM cannot hold two of them. `mix test.domain` runs unpartitioned over every app that owns a `domain/` and holds each module there to every line. Those two commands are the two numbers the design keeps: the runtime dependency count of `turnstile`, a test in its own suite, and `domain/` at 100 percent.

```
$ mix quality
<green>
$ mix test.domain
<every app that owns a domain/>, 0 failures
```

**The gate per package**, beyond its own `mix quality`, which is the root's minus the lock check.

| Package | Its own gate | What it proves |
|---|---|---|
| `turnstile` | `mix test --only committed` | The seam's refusals, `RepoCase` against the test repos, and the template against `Turnstile.Test.Fake` |
| `turnstile_rbac`, `turnstile_postgres`, `turnstile_cerbos`, `turnstile_fga` | `mix test` | The laws hold for that adapter against its real engine; the latency laws print a measurement |
| `turnstile_credo`, `turnstile_dev` | `mix test` | The two static checks, and the structure test over every package |
| `example` | `mix quality` | The domain, its contexts, and the scenario bodies every binding shares |
| `example_rbac`, `example_postgres`, `example_cerbos`, `example_fga` | `mix turnstile.schema_dump && git diff --exit-code priv/schema/`, then `mix test` | The committed schema is what the migrations produce, and every scenario runs and passes under that binding |

A change to a library package runs before the thin application that binds it. A change to a frozen table runs before the code that reads it: the freeze test in `turnstile` holds the adapter's callbacks, the struct fields, the law table, and the scenario table to their documents.

**CI** is one workflow, `nix develop` everywhere: `quality` with the tests across four partitions, each with its own cluster; `domain_coverage` alone, because a partitioned run measures a part; and one job per thin application that regenerates the schema dump, diffs it, and runs the scenarios with coverage. Every app's coverage threshold is 90 percent, and warnings are errors in every job.

**The split that stays.** The library emits and the system stores. A stage that adds a store to a library package is outside the design, not behind a flag.
