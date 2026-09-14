# Turnstile: delivery
*How one piece of work runs from start to commit, and the gate that ends it, as a command and its expected output. You are the agent running one.*

## 1. How a stage runs

1. Read `CLAUDE.md` and the files it lists, then whatever the work needs. Read nothing else.
2. Work on `main`, no worktree, no branch. Nothing runs beside you; stages are sequential.
3. Every command here runs inside `nix develop --command`, from the directory the gate names. Green means exit 0 with `warnings_as_errors`. The prompt `$` marks a command; the lines after it are what it prints, where a line in angle brackets describes the output rather than quoting it.
4. Run the gate of every package the work touched, then the root gate (§2).
5. Run the prose gate from `CLAUDE.md` over every document you changed. It prints `exit=1`.
6. Commit, unsigned, one idea per commit. The last commit message quotes every gate command and its output verbatim, then records what §4 asks for.

```
$ git -c commit.gpgsign=false commit -F -
```

A gate that fails is not worked around: report what failed and stop.

## 2. The root gate

At the root, `mix quality` is `hex.audit` first, because Hex requires it before any task that loads the application, then `format --check-formatted`, `compile --force --warnings-as-errors --all-warnings`, `credo --strict --all`, `xref graph --label compile-connected --fail-above 0`, `xref graph --format cycles --fail-above 0`, `deps.unlock --check-unused`, `deps.audit` with the one acknowledged advisory, `docs --warnings-as-errors`, and the test step, which runs each app's suite in an operating-system process of its own (`docs/code.md` §5).

```
$ mix quality
<green>
$ mix test.core
<every app that owns a core/>, 0 failures
```

Those two commands are `PLAN.md` §5's two numbers: the runtime dependency count of `turnstile`, which is a test in that package's own suite and runs under `mix quality`, and every module under a `core/` at 100% line coverage, which is what `mix test.core` measures. The root gate is part of every stage's gate.

## 3. The gate per package

Each package's own `mix quality` runs the same steps as the root's, minus the lock check, which is the umbrella's. Beyond it:

| Package | Its own gate, beyond `mix quality` | What it also proves |
|---|---|---|
| `turnstile` | `mix test --only committed` | The seam's refusals, `RepoCase` against the test repos, and the conformance template against `Turnstile.Test.Fake` |
| `turnstile_rbac`, `turnstile_postgres`, `turnstile_cerbos`, `turnstile_fga` | `mix test`, which runs `AdapterCase` against the real engine | The port's laws hold for that adapter, and its latency case prints a measurement without asserting it |
| `turnstile_relay` | `mix test --only committed` | Two connections contending for one runner's lock, and the migration taken down and raised again |
| `turnstile_credo`, `turnstile_dev` | `mix test` | The two static checks, and the structure test over every package's `lib` and `test/support` |
| `example` | `mix quality` and `mix sobelow --config --exit` | The domain, its contexts, and the scenario bodies every binding shares |
| `example_rbac`, `example_postgres`, `example_cerbos`, `example_fga` | `mix turnstile.schema_dump && git diff --exit-code priv/schema/`, then `mix test` and `mix sobelow --config --exit` | The committed schema is what the migrations produce, and every scenario of `docs/reference.md` §3a runs and passes under that binding |

A change to a library package runs before the thin application that binds it, and a change to `docs/reference.md` §3a runs before the code that reads the table, because the freeze test in `turnstile` holds the adapter's callbacks, the frozen struct fields, and the scenario ids to that document.

## 4. What a stage records

The last commit message of a stage records, beyond the gate output:

- A version pinned or re-verified, and where it was verified. Never a guessed version.
- A call the plan left open, and which way it went.
- Anything the next stage needs that no document says.

## 5. The split that stays

The library emits and the system stores. `turnstile` publishes a change event for each single-row write to an audited schema and a decision event for each call, and stores neither (`docs/reference.md` §7). A stage that adds a store to a library package is outside the design, not behind a flag: the adopter's consumer attaches a handler and owns the record. `Example.Siem` is the worked example of a consumer and holds its records in memory, which keeps the mapping under test without putting a schema version in any published package.

## 6. Deferred

The adoption guide, as educational material rather than as a package. A consumer that stores change events, if a team asks for replay, which is the adopter's to write and not this repository's. Neither changes a frozen interface.
