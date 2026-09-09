# Turnstile: code quality expectations
*What the code must look like outside the ports-and-adapters shape the plan already fixes: how we use Elixir's type system, what is banned, which knobs are turned, and what the CI gate runs. Rules are stated as rules; the reason follows in one sentence where it is not evident. Elixir 1.20.4 on OTP 29.0.6 is the target; 1.20 is the release that completed type inference of every construct, and 1.19 was the step before it.*

## 1. The type system: what it checks, and how we write so it can check more

**What Elixir 1.20 does.** It infers the type of whole function bodies, guards, and clauses (`case`, `cond`, and `with` with occurrence typing, maps with atom and domain keys, most of `Map` and tuple operations) without annotations, across applications, and reports two things: dead code (a clause that can never match) and *verified bugs* (a typing violation guaranteed to fail at runtime if reached). It is gradual: anything it cannot see is `dynamic()`, and `dynamic()` narrows as evidence accumulates. Calls between applications in the same project are typed as `dynamic()` when the callee has not compiled. The reference says it "generally avoids emitting false positive type violations", so **every type warning is a bug, and the build treats it as one** (§3).

**What it does not do yet.** No type annotations or signatures; user-provided signatures are the roadmap's next milestone, "planned for future releases" with no version named, and `@spec` and `@type` are documentation and Credo material, not checker input. No recursive or parametric types. No exhaustiveness checking beyond what inference proves. Values arriving from outside (JSON, YAML, Ecto params, `apply/3`, `Access`) are `dynamic()` until narrowed.

**Source.** The two paragraphs above were checked at S1 against the 1.20.4 changelog, <https://raw.githubusercontent.com/elixir-lang/elixir/v1.20.4/CHANGELOG.md>, and the gradual set-theoretic types reference, <https://raw.githubusercontent.com/elixir-lang/elixir/v1.20.4/lib/elixir/pages/references/gradual-set-theoretic-types.md>. The changelog supports whole-body inference, guards, inference across clauses, occurrence typing on `case`, `cond`, and `with`, atom and domain map keys, inference across applications, and the dead-code and verified-bug reports. It does not claim anonymous functions or protocol dispatch, so those were removed above. The reference is the source for the false-positive claim, for signatures as the next milestone with no release named, and for `dynamic()` on same-project calls.

**The consequence: write inferable code.** The checker proves what it can infer, so our job is to leave it evidence.

| Do | Because |
|---|---|
| Model every domain value as a struct with `@enforce_keys` (§2) | The checker knows struct keys: `%Decision{}.verdict` is checked, `decision.verdcit` is a verified bug, `%Decision{d \| unknown: 1}` is a verified bug |
| Put guards on every public function head: `is_struct(x, Subject)`, `is_atom/1`, `is_integer/1`, `is_binary/1` | Guards are the strongest source of inference; an unguarded head is `dynamic()` |
| Pattern-match in function heads and `case` on tagged tuples and struct patterns | Occurrence typing narrows each branch; `if Map.get(...)` narrows nothing |
| Enumerate with atom unions: `:allow \| :deny`, `:native \| :limited \| :unsupported` | The checker tracks atom sets and reports a missing or impossible clause |
| Return `{:ok, t} \| {:error, %Error{}}`; never `nil` for "not found", never a bare string for a reason | A union of tuples with a struct payload is fully checkable; `nil` and strings are not distinguishable from anything |
| Keep functions monomorphic: one shape in, one shape out | A function that accepts "a map or a struct or a keyword list" types as `dynamic()` everywhere it is used |
| Confine `dynamic()` sources to the edge and narrow immediately: decode, validate, build a struct | Everything downstream of a struct is typed; everything downstream of a map is not |
| Use `nil` only where "absent" is domain meaning, typed `t \| nil`, and handle it at every consumer | The checker will catch `nil.field`; it cannot tell you `nil` was a placeholder for "not computed yet" |
| Write a capability declaration as one function clause per record plus a fallback, never a map lookup | The checker read an empty-map lookup as returning only the default; clauses give it one atom set per rule |
| Type a role definition's actions as `[atom()]`, and every list literal as the checker allows | The checker cannot narrow a list literal from params; the declared type is the evidence |
| Set `infer_signatures: true` in every app's `elixirc_options` | Compiler options do not propagate from dependencies; each app must ask for its own signatures. On 1.20.4 the default is already `true`, so the setting documents the intent and protects against a future change of default |
| Recompile dependencies after an Elixir upgrade (`mix deps.compile --force`) | Signatures live in the compiled beams; stale deps mean stale inference |
| Still write `@spec` on every public function and `@type t` on every struct | Docs, Credo's `Specs` check, ex_doc, and the signature milestone when it lands; keep them true |

## 2. The bare-map ban

**Rule.** No bare map crosses a function boundary inside the library as a *record*, a map used as an ad hoc struct with a fixed set of atom keys. Records are structs.

**What a struct must have.** `@enforce_keys` naming every field that has no meaningful default; `defstruct` after it; `@type t :: %__MODULE__{...}` with every field typed; `@moduledoc`. Hand-written, no struct macro library: three lines of boilerplate is cheaper than a dependency, and the checker reads `defstruct` either way.

```elixir
defmodule Turnstile.Decision do
  @moduledoc "What the port said, when, from what state, under which rules."
  @enforce_keys [:id, :subject, :object, :operation, :verdict, :reason, :adapter, :policy_version,
                 :head_position, :applied_position, :operation_id, :at]
  defstruct @enforce_keys

  @type verdict :: :allow | :deny | :scoped
  @type t :: %__MODULE__{
          id: Turnstile.Id.t(), subject: Turnstile.Subject.t(), object: Turnstile.Object.ref(),
          operation: atom(), verdict: verdict(), reason: Turnstile.Reason.t(), adapter: module(),
          policy_version: Turnstile.PolicyVersion.ref(),
          head_position: non_neg_integer() | nil, applied_position: non_neg_integer() | nil,
          operation_id: Turnstile.Id.t(), at: DateTime.t()
        }
end
```

Two positions, not one: the head at decision time and the position the adapter's state had applied, equal unless the adapter projects, both `nil` in ledger mode none (`docs/reference.md` §7).

**Structs the reference names**, each defined this way: `%Turnstile.Decision{}`, `%Turnstile.FactEvent{}` (§8), `%Turnstile.PolicyVersion{}` (§5), `%Turnstile.Exemption{kind: :declared | :library}` (§6), `%Turnstile.Subject{kind: :user | :non_person_entity | :privileged}`, `%Turnstile.Config{}` (§15); the errors `Turnstile.Error.Unmediated`, `Turnstile.Error.Engine`, `Turnstile.Error.Unsupported`, `Turnstile.Error.NotAuthorized`, `Turnstile.Error.Invalid`; the behaviours `Turnstile.Adapter`, `Turnstile.Ledger`, `Turnstile.Ledger.Dialect` (seven questions, §11), `Turnstile.Projection` (`checkpoint/1`, `drain_once/1`, `rebuild/1`, `reconcile/1`), `Turnstile.Clock`, `Turnstile.Capabilities` (`capability/1`), `Turnstile.Fga.Client`, `Turnstile.Fga.TupleMapping`.

**On structs, these are banned:** `Map.put/3`, `Map.merge/2`, `Map.update/4`, `Map.delete/2`, `Access` (`s[:k]`), `Map.from_struct/1` outside serializers. Update with `%S{s | field: v}`; the checker verifies the key. Build with the literal, or at an edge with the raising variant of `struct/2`, never the plain one, which drops unknown keys silently.

**Two things that are not records, and stay maps.**
- *Dictionaries*: a map keyed by data, not by field name: `%{user_id => [permission]}`, `%{position => event}`. Typed by the checker since 1.20. Prefer `MapSet` for sets.
- *Edges*: the top-level telemetry metadata and measurements maps (telemetry's contract), Ecto changeset params, decoded JSON and YAML, Cerbos request payloads, OpenFGA request and response bodies, `.credo.exs`-style config. Each edge has exactly one function that converts map to struct (`from_map/1`, validating, returning `{:ok, t} | {:error, %Turnstile.Error.Invalid{}}`) or struct to map (`to_map/1`, `Jason.Encoder` derived with `only:`). The struct is what travels; inside telemetry metadata the payload is `%{event: %Turnstile.Decision{}}`, a struct inside the contract map.

**Options are schemas, not maps or free keyword lists.** Every function that takes options declares a `NimbleOptions` schema: compile-time documentation, runtime validation with a precise error, and a generated typespec. `Keyword.validate/2` is acceptable for two or three boolean flags. `opts[:foo]` without a schema is a Credo failure. The seam's `turnstile:` option is a schema accepting `%Turnstile.Decision{}`, `{:exempt, reason}` with a non-empty string, or `{:exempt, :library}`, the last accepted only from a `Turnstile.*` caller, which the seam checks.

**Events.** A fact event is `%Turnstile.FactEvent{kind, subject_ref, object_ref, attribute, old, new, position, operation_id, at, by}` with `kind` one of `:subject_attribute`, `:object_attribute`, `:relationship`, `:policy_version`; `old` and `new` are typed per kind, and for `:policy_version` `new` is `%Turnstile.PolicyVersion{}`. A decision event is `%Turnstile.Decision{}`. Never `%{type: "assignment_granted", payload: %{}}`. Serialization to a map happens in the telemetry handler and the ledger writer, nowhere else.

**Configuration**. `%Turnstile.Config{}` is validated once at boot from a `NimbleOptions` schema and is the only runtime configuration the library reads. Core reads the adapter from it at boot; one build serves every adapter, and Tier 1 binds one per test module through the override. Its fields, as `docs/reference.md` §15 lists them: `adapter` (`module | {module, keyword}`, the options validated by the adapter's own schema), `ledger` (`{Turnstile.Ledger.Ecto, repo: module, owner_repo: module} | :none`), `ledger_counter` (default `"default"`, a test override), `clock`, and `caps` (one keyword list). `Application.get_env/2` inside a function body is banned; everything is read once into the struct. `Application.compile_env/3` is reserved for the example's generated per-operation functions and appears nowhere else. Tests override any field through `Turnstile.Test.with_config/1` (for the rest of the calling process) and `with_config/2` (around a function, restored after); both write one process-dictionary key, and the seam's resolver reads it from `self()` and then the `$callers` chain, falling back to the boot struct.

## 3. The knobs

Elixir has no `strict: true`; it has a dozen switches. All of them are on.

| Knob | Where | Setting | What it buys |
|---|---|---|---|
| Elixir version | `mix.exs`, `flake.nix` | `elixir: "~> 1.20.4"`; OTP 29.0.6 pinned by the flake (verified 2026-09-07 against `pkgs/development/interpreters/erlang/29.nix` on `nixos-unstable`) | The complete inference milestone; 1.20 needs OTP 27 to 29 |
| Environment | `flake.nix`, `.envrc`, CI | nixpkgs `nixos-unstable`, locked, provides Elixir, OTP, Postgres 18, and OpenFGA; Cerbos is fetched from its release archive; CI runs `nix develop --command mix quality` | Dev and CI are the same closure; no Docker (`docs/testing.md` §2) |
| Warnings are errors | every app's `elixirc_options` | `warnings_as_errors: true` | Type warnings, unused variables, deprecated calls all fail the build |
| Signature inference | every app's `elixirc_options` | `infer_signatures: true` | Cross-module, cross-app inference for our own code |
| Undefined-call allowlist | `elixirc_options` | `no_warn_undefined: []`, empty | Nothing is silenced; the deprecated `xref: [exclude:]` is not used |
| Full, fresh type check in CI | CI | `mix compile --force --warnings-as-errors --all-warnings` | Incremental compiles skip unchanged modules; CI checks all of them |
| Tests fail on warnings | CI | `mix test --warnings-as-errors` | A warning printed during a test run is a failure |
| Coverage threshold | `mix.exs` `test_coverage` | `[summary: [threshold: 90]]`, `ignore_modules` for the generated per-operation modules | `mix test --cover` fails below the line |
| Formatting | `.formatter.exs`, CI | `import_deps`, `plugins: [Styler]`; `mix format --check-formatted` | Styler rewrites to one set of idioms (alias order, pipe shape, `case` and `if` normalisation) so style is not reviewed by humans |
| Credo | `.credo.exs`, CI | `mix credo --strict --all`; every check enabled, each disabled check carries a comment saying why | See the list below |
| Module dependencies | each app's root module | `use Boundary` with explicit `deps:` and `exports:`; the top-layer rule keeps `authorize`, `check`, `batch`, `explain`, and `review` off `ecto_sql` | Architecture is compile-checked, not reviewed |
| Compile-time cycles | CI | `mix xref graph --label compile-connected --fail-above 0` and `--format cycles --fail-above 0` | No compile-time dependency cycles; keeps incremental builds and the type checker fast |
| Dependency hygiene | CI | `mix deps.unlock --check-unused`, `mix hex.audit`, `mix deps.audit` (`mix_audit`) | No orphaned locks, no retired packages, no known CVEs except one acknowledged by id in `mix.exs` with the reason it does not apply and the check that no patched release exists |
| Docs | CI | `mix docs --warnings-as-errors` | A broken reference in `@doc` fails; `@moduledoc` and `@doc` on every public module and function (Credo enforces) |
| Callbacks | code | `@impl true` on every callback implementation (Credo `ImplTrue`) | The compiler then warns on a callback that is not one and a function that should be |
| Phoenix security | CI, `turnstile_example` and the thin apps | `mix sobelow --config --exit` | The example is the thing an assessor reads first |
| Property tests | Tier 1 | `stream_data` for the port guarantees | Scope fidelity and deny-by-default are properties over random subjects and objects, not five examples |

**Hex pins**, verified against hex.pm on 2026-09-07; `mix.lock` is the pin and S0 re-verifies each one:

| Package | Version | Released | Note |
|---|---|---|---|
| `nimble_options` | 1.1.1 | 2024-05-25 | |
| `mox` | 1.3.1 | 2026-08-31 | 1.3.0 and 1.3.1 both landed in the two weeks before verification |
| `stream_data` | 1.4.0 | 2026-07-14 | |
| `boundary` | 0.10.4 | 2024-09-25 | two years without a release; S1 confirms it compiles and reports on Elixir 1.20 before the top-layer rule depends on it |
| `styler` | 1.12.2 | 2026-07-30 | |
| `muontrap` | 2.0.0 | 2026-08-13 | a new major; 1.8.0 was the last 1.x. The `MuonTrap.Daemon` API the cluster and the Cerbos helper use is checked against the 2.0 changelog at S0 before either is written |
| `mneme` | not used | 0.10.2, 2025-01-24 | dropped: no release in nineteen months, unverified on 1.20; golden files with plain assertions instead (`docs/testing.md` §6) |

Credo checks that are off by default and are on here: `Readability.Specs` (every public function has a `@spec`), `Readability.StrictModuleLayout`, `Readability.ImplTrue`, `Readability.WithSingleClause`, `Refactor.WithClauses`, `Refactor.Apply`, `Refactor.ABCSize`, `Refactor.CyclomaticComplexity`, `Refactor.Nesting` at strict thresholds, `Warning.UnsafeToAtom`, `Warning.MapGetUnsafePass`, `Design.AliasUsage`, `Design.TagTODO` and `TagFIXME` as failures. Custom, shipped in core: `Turnstile.Credo.NoRawSQL` and `UnmediatedRepo` (the plan's two; the second excepts the owner-role repo), plus `Turnstile.Credo.StructsEnforceKeys` (a `defstruct` without `@enforce_keys` and `@type t` fails) and `Turnstile.Credo.NoRecordMaps` (a map literal with two or more atom keys outside an edge module is flagged; advisory, because it is a heuristic).

**Deliberately off.** Dialyzer: the compiler's checker has the sound half of what Dialyzer offered and none of the noise, and the project does not carry PLTs. Runtime type-check libraries (Norm, TypeCheck, Domo): structs plus `NimbleOptions` at the edges cover what they would, without runtime cost inside the request path. `module_definition: :interpreted`: a compile-speed option, not a correctness one; leave the default unless build times say otherwise.

## 4. Idioms

**Module layout**, enforced by `StrictModuleLayout` in the order Styler writes: `@moduledoc`; `@behaviour`; `use`; `import`; `alias`; `require`; module attributes; `@enforce_keys` and `defstruct`; `@type`s, after the struct because `@type t` names `%__MODULE__{}` and the compiler refuses that before `defstruct`; `@callback`s; public functions; private functions. A function with `@doc false` counts as private. One module, one concept; no `Helpers` or `Utils` modules; a function belongs to the struct or behaviour it serves.

**Behaviours, not duck typing.** Every pluggable thing is a `@behaviour` with `@callback`s and `@optional_callbacks`; implementations mark `@impl true`; surfaces are enumerated with `Module.behaviour_info/1`, never hand-listed. Protocols only for dispatch on data type (`Turnstile.Explainable`), never as a substitute for a behaviour. **Optional callbacks are answered at runtime**: `explain` is optional, core checks `function_exported?/3` and returns `{:error, %Turnstile.Error.Unsupported{}}` when it is absent; no function is generated or omitted according to the adapter, so one build serves every adapter.

**Fakes**. A fake, stub, or in-memory implementation returns a value of the real type wherever the real implementation returns one; it never raises in its place. `Turnstile.Adapter.Fake`'s `scope` returns a real `dynamic`, its `explain` returns `{:error, %Turnstile.Error.Unsupported{}}`; `Turnstile.Fga.Client.Fake` returns the same `{:ok, t} | {:error, %Turnstile.Error.Engine{}}` shapes as the real client; the in-memory ledger returns what the Ecto ledger returns. The reason is the checker: a stub that raised typed every call site as a certain crash under warnings-as-errors.

**Capability records**. A thin app's `Turnstile.Capabilities` implementation is one `capability/1` clause per record plus a fallback clause; the record is `{level, by: component, note: String.t()}` with `level` in `:native | :limited | :unsupported` and `component` in `:adapter | :seam | :database | :engine | :application`. Never a map lookup, never a module attribute holding the table.

**Errors.** An expected failure is a value: `{:error, %Turnstile.Error.NotAuthorized{}}`, where every error module is `defexception` with `@enforce_keys` and a `message/1`. A programmer error raises. Bang variants raise the same struct. The port never raises on the request path, the plan's fail-closed guarantee, so port errors are values without exception; the seam's refusal, `Turnstile.Error.Unmediated`, raises, because an unmediated call is a programming error. No `{:error, :some_atom}`, no `{:error, "string"}`, no `nil` for "not found".

**Booleans.** Predicates end in `?` and return exactly `true` or `false`; guard-safe predicates are `is_`-prefixed macros only when they must be usable in guards. No double-bang coercion.

**Atoms.** Never created from external input: `String.to_atom/1` is banned; `String.to_existing_atom/1` only behind an explicit allowlist. `Ecto.Enum` for atom-valued schema fields, so the database column and the code agree on the set.

**Nil.** Not a return value. In a struct, only as `t | nil` where absence is meaning (`head_position: nil` in ledger mode none), and every consumer branches on it explicitly.

**Control flow.** `with` for a chain of results; every `else` clause names the shape it handles; no `with` with one clause. `case` over `cond` where there is a value; `cond` over nested `if`. No `try/rescue` for control flow; `rescue` only at supervision or edge boundaries, and it re-raises what it does not understand.

**Reflection and metaprogramming.** `apply/3`, `Module.definitions_in/1`, `__info__/1`, and `Code.*` are confined to the places the plan needs them and allowlisted in Credo by module: `Turnstile.Conformance.RepoCase` and the example's per-operation function generation. **The seam's overrides and `prepare_query/3` are defined in `@before_compile`** with `defoverridable` and `super`; the surface is a plain list in `Turnstile.Repo.Surface`, and `RepoCase` diffs it against `Repo.__info__(:functions)` at test time (`docs/reference.md` §6). Every macro has a function it calls; a macro's body is dispatch, not logic. `use Turnstile.Repo`, `use Turnstile.Schema` (`object_type/1`, `carries/1`, `fact/2`, `relationship/1`), the `scenario` macro, and the per-operation generator are the only public macros.

**Processes.** Library code owns no long-lived processes except the reconcile scheduler and the projector, both started by the thin app, both startable unnamed with injected repo, ledger, clock, and client; state in any GenServer is a struct; the process dictionary is touched in the seam's dynamic-repo entry and in the test configuration resolver, nowhere else. The RBAC adapter's boot-time policy-version append runs inside a transaction that takes the counter row, so it cannot race across nodes, and in mode none it emits telemetry only. No `Process.sleep/1` in tests: deadline loops with `assert_receive` or the polling helper, which is also how revocation latency is measured.

**Ecto.** `@primary_key` and field types explicit in every schema; `Ecto.Enum` for atoms; changesets cast at the edge and validated before anything else sees the data; `Repo` only through the seam, or through the owner-role repo for the library's own writes. The `dynamic` that `scope` returns is opaque to the checker, the one place we accept it, and the adapter that builds it is covered by the scope-fidelity property, not by types. An upsert on a fact schema is refused; the bulk API is `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, `bulk_insert/3`.

**Documentation.** `@doc` on every public function, with a doctest where the example is cheap and true; `@doc false` for functions that must be public for a macro; `@typedoc` on every public type. Test names are the scenario id and sentence from `docs/reference.md` §1 and §3a.

**Naming**. `Turnstile.` for library modules; `Example.` for `turnstile_example`; `ExampleRbac.`, `ExamplePostgres.`, `ExampleCerbos.`, `ExampleFga.` for the thin apps. A struct's module is a noun (`Decision`, `FactEvent`); a behaviour's is a role (`Adapter`, `Ledger`, `Dialect`, `Projection`); an error's is `Turnstile.Error.<What>`; a Credo check's is `Turnstile.Credo.<Rule>`. "Adapter", never "provider". No abbreviations in public names.

## 5. The gate

One alias runs everything; a pull request is mergeable when it is green and the diff carries no new `# credo:disable` or `@doc false` without a sentence of justification beside it.

```elixir
# mix.exs (umbrella root and each app)
def project do
  [
    elixir: "~> 1.20.4",
    elixirc_options: [warnings_as_errors: true, infer_signatures: true, no_warn_undefined: []],
    test_coverage: [summary: [threshold: 90], ignore_modules: [~r/\.Generated\./, ~r/TestRepos\./]],
    aliases: aliases(),
    hex: [ignore_advisories: ["CVE-2026-32686"]], # decimal, no patched release; the reason sits beside it in the real file
    ...
  ]
end

defp aliases do
  [
    quality: [
      "hex.audit", # first: Hex requires it before any task that loads the application
      "format --check-formatted",
      "compile --force --warnings-as-errors --all-warnings",
      "credo --strict --all",
      "xref graph --label compile-connected --fail-above 0",
      "xref graph --format cycles --fail-above 0",
      "deps.unlock --check-unused", # in the root alias only: the lock is the umbrella's, and a child's check flags what its siblings lock
      "deps.audit --ignore-advisory-ids GHSA-rhv4-8758-jx7v", # the same advisory, by its GitHub id
      "docs --warnings-as-errors",
      "test --warnings-as-errors --cover" # test_helper starts the ephemeral Postgres, Cerbos, and OpenFGA (docs/testing.md §3 to §4)
    ]
  ]
end
```

```elixir
# .formatter.exs
[
  import_deps: [:ecto, :ecto_sql, :phoenix, :nimble_options],
  plugins: [Styler],
  inputs: ["{mix,.formatter,.credo}.exs", "{config,lib,test}/**/*.{ex,exs}", "apps/*/{lib,test,config}/**/*.{ex,exs}"]
]
```

`turnstile_example` and each thin app add `sobelow --config --exit` to their own alias. The lock check runs at the root alone, where every app's dependencies are known; the root's `quality` is part of every stage's gate. Tier 1's property tests and shape tests run under `mix test`, so the gate checks the seam's shape too; `mix turnstile.bench` is on demand and not part of the gate. The thin-app CI jobs (`docs/testing.md` §7) run after `quality` and add the schema dump.

## 6. Known gaps, and what covers each

| Gap | Covered by |
|---|---|
| `@spec` is not checker input yet | Credo `Specs` keeps them present; review keeps them true; the signature milestone will use them |
| `Ecto.Query.DynamicExpr` is opaque | The scope-fidelity property test in Tier 1 |
| Maps from JSON, YAML, params are `dynamic()` | One `from_map/1` per edge, validating into a struct |
| `apply/3` and reflection hide call sites from the checker | Confined to the allowlisted modules, each with an enumeration-driven test; `RepoCase` reads the compiled Repo's exports at test time, where it sees everything |
| An empty-map lookup types as its default alone | Capability declarations are function clauses |
| A list literal cannot be narrowed from params | Declared list types, `[atom()]` for a role's actions |
| A stub that raises types every call site as a crash | Fakes return values of the real type |
| No parametric types, so `Result.t(inner)` cannot be expressed | Concrete `@type`s per use; not worth a workaround |
| Compiler options do not propagate from dependencies | `infer_signatures: true` in every app; documented for adopters in core's README |
| Signatures from stale dependency beams | `mix deps.compile --force` on Elixir upgrades, in the bump procedure |
| The checker reports only verified bugs, not everything a stricter language would | Structs, guards, atom unions, and the `NoRecordMaps` check make more of the program verifiable; that is the whole of §1 and §2 |
