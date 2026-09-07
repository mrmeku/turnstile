# Turnstile — code quality expectations
*Mode: Reference. What the code must look like outside the ports-and-adapters shape the plan already fixes: how we use Elixir's type system, what is banned, which knobs are turned, and what the CI gate runs. Rules are stated as rules; the reason follows in one sentence where it isn't obvious. Elixir 1.20 is the target — it is the release that completed type inference of every construct; 1.19 was the step before it.*

## 1. The type system: what it checks, and how we write so it can check more

**What Elixir 1.20 does.** It infers the type of every construct — whole functions, guards, anonymous functions, protocol dispatch, `case`/`cond`/`with` with occurrence typing, maps with atom and non-atom keys, most of `Map` and tuple operations — without annotations, across applications, and reports two things: dead code (a clause that can never match) and *verified bugs* (a typing violation guaranteed to fail at runtime if reached). It is gradual: anything it cannot see is `dynamic()`, and `dynamic()` narrows as evidence accumulates. It is tuned for near-zero false positives, so **every type warning is a bug, and the build treats it as one** (§3).

**What it does not do yet.** No type annotations or signatures — those come after 1.21/1.22; `@spec` and `@type` are documentation and Credo material, not checker input. No recursive or parametric types. No exhaustiveness checking beyond what inference proves. Values arriving from outside — JSON, YAML, Ecto params, `apply/3`, `Access` — are `dynamic()` until narrowed.

**The consequence: write inferable code.** The checker proves what it can infer, so our job is to leave it evidence.

| Do | Because |
|---|---|
| Model every domain value as a struct with `@enforce_keys` (§2) | The checker knows struct keys: `%Decision{}.verdict` is checked, `decision.verdcit` is a verified bug, `%Decision{d \| unknown: 1}` is a verified bug |
| Put guards on every public function head — `is_struct(x, Subject)`, `is_atom/1`, `is_integer/1`, `is_binary/1` | Guards are the strongest source of inference; an unguarded head is `dynamic()` |
| Pattern-match in function heads and `case` on tagged tuples and struct patterns | Occurrence typing narrows each branch; `if Map.get(...)` narrows nothing |
| Enumerate with atom unions — `:allow \| :deny`, `:native \| :limited \| :unsupported` | The checker tracks atom sets and reports a missing or impossible clause |
| Return `{:ok, t} \| {:error, %Error{}}`; never `nil` for "not found", never a bare string for a reason | A union of tuples with a struct payload is fully checkable; `nil` and strings are not distinguishable from anything |
| Keep functions monomorphic: one shape in, one shape out | A function that accepts "a map or a struct or a keyword list" types as `dynamic()` everywhere it is used |
| Confine `dynamic()` sources to the edge and narrow immediately: decode → validate → build a struct | Everything downstream of a struct is typed; everything downstream of a map is not |
| Use `nil` only where "absent" is domain meaning, typed `t \| nil`, and handle it at every consumer | The checker will catch `nil.field`; it cannot tell you `nil` was a placeholder for "not computed yet" |
| Set `infer_signatures: true` in every app's `elixirc_options` | Compiler options do not propagate from dependencies; each app must ask for its own signatures ⟨verify the 1.20 default⟩ |
| Recompile dependencies after an Elixir upgrade (`mix deps.compile --force`) | Signatures live in the compiled beams; stale deps mean stale inference |
| Still write `@spec` on every public function and `@type t` on every struct | Docs, Credo's `Specs` check, ex_doc, and the signature milestone when it lands; keep them true |

## 2. The bare-map ban

**Rule.** No bare map crosses a function boundary inside the library as a *record* — a map used as an ad hoc struct, with a fixed set of atom keys. Records are structs.

**What a struct must have.** `@enforce_keys` naming every field that has no meaningful default; `defstruct` after it; `@type t :: %__MODULE__{...}` with every field typed; `@moduledoc`. Hand-written, no struct macro library: three lines of boilerplate is cheaper than a dependency, and the checker reads `defstruct` either way.

```elixir
defmodule Turnstile.Decision do
  @moduledoc "What the port said, when, from what state, under which rules."
  @enforce_keys [:id, :subject, :object, :operation, :verdict, :reason, :adapter, :policy_version, :position, :at]
  defstruct @enforce_keys

  @type verdict :: :allow | :deny | :scoped
  @type t :: %__MODULE__{
          id: Turnstile.Id.t(), subject: Turnstile.Subject.t(), object: Turnstile.Object.ref(),
          operation: atom(), verdict: verdict(), reason: Turnstile.Reason.t(), adapter: module(),
          policy_version: Turnstile.PolicyVersion.ref(), position: non_neg_integer() | nil, at: DateTime.t()
        }
end
```

**On structs, these are banned:** `Map.put/3`, `Map.merge/2`, `Map.update/4`, `Map.delete/2`, `Access` (`s[:k]`), `Map.from_struct/1` outside serializers. Update with `%S{s | field: v}` — the checker verifies the key. Build with the literal or `struct!/2` at an edge, never `struct/2`, which drops unknown keys silently.

**Two things that are not records, and stay maps.**
- *Dictionaries*: a map keyed by data, not by field name — `%{user_id => [permission]}`, `%{position => event}`. Typed by the checker since 1.20. Prefer `MapSet` for sets.
- *Edges*: the top-level telemetry metadata and measurements maps (telemetry's contract), Ecto changeset params, decoded JSON/YAML, OSCAL and KSI output, Cerbos request payloads, `.credo.exs`-style config. Each edge has exactly one function that converts map → struct (`from_map/1`, validating, returning `{:ok, t} | {:error, %Turnstile.Error.Invalid{}}`) or struct → map (`to_map/1`, `Jason.Encoder` derived with `only:`). The struct is what travels; inside telemetry metadata the payload is `%{event: %Turnstile.Decision{}}`, a struct inside the contract map.

**Options are schemas, not maps or free keyword lists.** Every function that takes options declares a `NimbleOptions` schema: compile-time documentation, runtime validation with a precise error, and a generated typespec. `Keyword.validate!/2` is acceptable for two or three boolean flags. `opts[:foo]` without a schema is a Credo failure. The seam's `turnstile:` option — a `%Turnstile.Decision{}` or `{:exempt, reason}` — is a schema, and `reason` is a non-empty string.

**Events.** Fact events and decision events are structs with a `kind` atom and a per-kind payload struct — never `%{type: "assignment_granted", payload: %{}}`. Serialization to a map happens in the telemetry handler and the ledger writer, nowhere else.

**Configuration** is a struct — `%Turnstile.Config{}` — validated once at boot from a `NimbleOptions` schema. `Application.get_env/2` inside a function body is banned; the adapter is bound with `Application.compile_env/3` (the plan's compile-time binding); everything else is read once into the struct.

## 3. The knobs

Elixir has no `strict: true`; it has a dozen switches. All of them are on.

| Knob | Where | Setting | What it buys |
|---|---|---|---|
| Elixir version | `mix.exs`, `flake.nix` | `elixir: "~> 1.20.4"` ⟨verify latest patch⟩; OTP 28 pinned by the flake | The complete inference milestone; 1.20 needs OTP 27+ |
| Environment | `flake.nix`, `.envrc`, CI | a locked nixpkgs provides Elixir, OTP, Postgres, and Cerbos; CI runs `nix develop --command mix quality` | Dev and CI are the same closure; no Docker (`TESTING.md`) |
| Warnings are errors | every app's `elixirc_options` | `warnings_as_errors: true` | Type warnings, unused variables, deprecated calls all fail the build |
| Signature inference | every app's `elixirc_options` | `infer_signatures: true` | Cross-module, cross-app inference for our own code |
| Undefined-call allowlist | `elixirc_options` | `no_warn_undefined: []` — empty | Nothing is silenced; the deprecated `xref: [exclude:]` is not used |
| Full, fresh type check in CI | CI | `mix compile --force --warnings-as-errors --all-warnings` | Incremental compiles skip unchanged modules; CI checks all of them |
| Tests fail on warnings | CI | `mix test --warnings-as-errors` | A warning printed during a test run is a failure |
| Coverage threshold | `mix.exs` `test_coverage` | `[summary: [threshold: 90]]`, `ignore_modules` for generated per-operation modules | `mix test --cover` fails below the line |
| Formatting | `.formatter.exs`, CI | `import_deps`, `plugins: [Styler]`; `mix format --check-formatted` | Styler rewrites to one set of idioms — alias order, pipe shape, `case`/`if` normalisation — so style is not reviewed by humans |
| Credo | `.credo.exs`, CI | `mix credo --strict --all`; every check enabled, each disabled check carries a comment saying why | See the list below |
| Module dependencies | each app's root module | `use Boundary` with explicit `deps:` and `exports:`; the top-layer rule from the plan | Architecture is compile-checked, not reviewed |
| Compile-time cycles | CI | `mix xref graph --label compile-connected --fail-above 0` and `--format cycles --fail-above 0` | No compile-time dependency cycles; keeps incremental builds and the type checker fast |
| Dependency hygiene | CI | `mix deps.unlock --check-unused`, `mix hex.audit`, `mix deps.audit` (`mix_audit`) | No orphaned locks, no retired packages, no known CVEs |
| Docs | CI | `mix docs --warnings-as-errors` | A broken reference in `@doc` fails; `@moduledoc` and `@doc` on every public module and function (Credo enforces) |
| Callbacks | code | `@impl true` on every callback implementation (Credo `ImplTrue`) | The compiler then warns on a callback that isn't one and a function that should be |
| Phoenix security | CI, example only | `mix sobelow --config --exit` | The example is the thing an assessor reads first |
| Property tests | Tier 1 | `stream_data` for the port guarantees | Scope fidelity and deny-by-default are properties over random subjects and objects, not five examples |

Credo checks that are off by default and are on here: `Readability.Specs` (every public function has a `@spec`), `Readability.StrictModuleLayout`, `Readability.ImplTrue`, `Readability.WithSingleClause`, `Refactor.WithClauses`, `Refactor.Apply`, `Refactor.ABCSize`, `Refactor.CyclomaticComplexity`, `Refactor.Nesting` at strict thresholds, `Warning.UnsafeToAtom`, `Warning.MapGetUnsafePass`, `Design.AliasUsage`, `Design.TagTODO` and `TagFIXME` as failures. Custom, shipped in core: `Turnstile.Credo.NoRawSQL` and `UnmediatedRepo` (the plan's two), plus `Turnstile.Credo.StructsEnforceKeys` (a `defstruct` without `@enforce_keys` and `@type t` fails) and `Turnstile.Credo.NoRecordMaps` (a map literal with two or more atom keys outside an edge module is flagged — advisory, because it is a heuristic).

**Deliberately off.** Dialyzer: the compiler's checker has the sound half of what Dialyzer offered and none of the noise, and the project does not carry PLTs. Runtime type-check libraries (Norm, TypeCheck, Domo): structs plus `NimbleOptions` at the edges cover what they would, without runtime cost inside the request path. `module_definition: :interpreted`: a compile-speed option, not a correctness one; leave the default unless build times say otherwise.

## 4. Idioms

**Module layout**, enforced by `StrictModuleLayout`: `@moduledoc`; `use`; `import`; `alias`; `require`; `@behaviour`; module attributes; `@type`s; `@enforce_keys` and `defstruct`; `@callback`s; public functions; private functions. One module, one concept; no `Helpers` or `Utils` modules — a function belongs to the struct or behaviour it serves.

**Behaviours, not duck typing.** Every pluggable thing is a `@behaviour` with `@callback`s and `@optional_callbacks`; implementations mark `@impl true`; surfaces are enumerated with `Module.behaviour_info/1`, never hand-listed. Protocols only for dispatch on data type (`Turnstile.Explainable`), never as a substitute for a behaviour.

**Errors.** An expected failure is a value: `{:error, %Turnstile.Error.NotAuthorized{}}`, where every error module is `defexception` with `@enforce_keys` and a `message/1`. A programmer error raises. `!` variants raise the same struct. The port never raises on the request path — the plan's fail-closed guarantee — so port errors are values without exception. No `{:error, :some_atom}`, no `{:error, "string"}`, no `nil` for "not found".

**Booleans.** Predicates end in `?` and return exactly `true` or `false`; guard-safe predicates are `is_`-prefixed macros only when they must be usable in guards. No `!!`.

**Atoms.** Never created from external input: `String.to_atom/1` is banned; `String.to_existing_atom/1` only behind an explicit allowlist. `Ecto.Enum` for atom-valued schema fields, so the database column and the code agree on the set.

**Nil.** Not a return value. In a struct, only as `t | nil` where absence is meaning — `position: nil` in ledger mode none — and every consumer branches on it explicitly.

**Control flow.** `with` for a chain of results; every `else` clause names the shape it handles; no `with` with one clause. `case` over `cond` where there is a value; `cond` over nested `if`. No `try/rescue` for control flow; `rescue` only at supervision or edge boundaries, and it re-raises what it does not understand.

**Reflection and metaprogramming.** `apply/3`, `Module.definitions_in/1`, `__info__/1`, and `Code.*` are confined to the three places the plan needs them — the seam's surface check, the Tier 1 sweep, the generator's per-operation function generation — and are allowlisted in Credo by module. Every macro has a function it calls; a macro's body is dispatch, not logic. `use Turnstile.Repo` and the per-operation generator are the only public macros.

**Processes.** Library code owns no long-lived processes except the reconcile scheduler; state in any GenServer is a struct; the process dictionary is touched only where Ecto's dynamic-repo mechanism requires it, in the seam, and nowhere else. No `Process.sleep/1` in tests — deadline loops with `assert_receive` or a polling helper, which is also how revocation latency is measured.

**Ecto.** `@primary_key` and field types explicit in every schema; `Ecto.Enum` for atoms; changesets cast at the edge and validated before anything else sees the data; `Repo` only through the seam. The `dynamic` that `scope` returns is opaque to the checker — the one place we accept it — and the adapter that builds it is covered by the scope-fidelity property, not by types.

**Documentation.** `@doc` on every public function, with a doctest where the example is cheap and true; `@doc false` for functions that must be public for a macro; `@typedoc` on every public type. Test names are the scenario sentences from the plan.

**Naming.** `Turnstile.` namespace everywhere; a struct's module is a noun (`Decision`, `FactEvent`); a behaviour's is a role (`Adapter`, `Ledger`, `Dialect`); an error's is `Turnstile.Error.<What>`; a Credo check's is `Turnstile.Credo.<Rule>`. No abbreviations in public names.

## 5. The gate

One alias runs everything; a pull request is mergeable when it is green and the diff carries no new `# credo:disable` or `@doc false` without a sentence of justification beside it.

```elixir
# mix.exs (umbrella root and each app)
def project do
  [
    elixir: "~> 1.20.4",
    elixirc_options: [warnings_as_errors: true, infer_signatures: true, no_warn_undefined: []],
    test_coverage: [summary: [threshold: 90], ignore_modules: [~r/^Turnstile\.Generated\./]],
    aliases: aliases(),
    ...
  ]
end

defp aliases do
  [
    quality: [
      "format --check-formatted",
      "compile --force --warnings-as-errors --all-warnings",
      "credo --strict --all",
      "xref graph --label compile-connected --fail-above 0",
      "xref graph --format cycles --fail-above 0",
      "deps.unlock --check-unused",
      "hex.audit",
      "deps.audit",
      "docs --warnings-as-errors",
      "test --warnings-as-errors --cover" # test_helper starts the ephemeral Postgres and Cerbos (TESTING.md §3–4)
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

The example app adds `sobelow --config --exit` to its own alias. Tier 1's property tests and shape tests run under `mix test`, so the gate checks the seam's shape too; `mix turnstile.bench` is on demand and not part of the gate.

## 6. Known gaps, and what covers each

| Gap | Covered by |
|---|---|
| `@spec` is not checker input yet | Credo `Specs` keeps them present; review keeps them true; the signature milestone will use them |
| `Ecto.Query.DynamicExpr` is opaque | The scope-fidelity property test in Tier 1 |
| Maps from JSON, YAML, params are `dynamic()` | One `from_map/1` per edge, validating into a struct |
| `apply/3` and reflection hide call sites from the checker | Confined to three allowlisted modules, each with an enumeration-driven test |
| No parametric types, so `Result.t(inner)` cannot be expressed | Concrete `@type`s per use; not worth a workaround |
| Compiler options do not propagate from dependencies | `infer_signatures: true` in every app; documented for adopters in the adoption guide, step 0 |
| Signatures from stale dependency beams | `mix deps.compile --force` on Elixir upgrades, in the bump procedure |
| The checker reports only verified bugs, not everything a stricter language would | Structs, guards, atom unions, and the `NoRecordMaps` check make more of the program verifiable; that is the whole of §1 and §2 |
