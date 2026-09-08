# Handoff
*Mode: Reference. Written from scratch by the agent that finished the last task; the next agent reads it before starting.*

## Task

Write `docs/testing.md`, `docs/code.md`, `docs/writing.md`, and `CLAUDE.md` for v9, and remove every reference to the earlier implementation from the documents.

## Done

- `docs/testing.md` (129 lines): v8 TESTING revised. §2 states the flake pins with where each was verified and the macOS Gatekeeper note; §3 adds the counter table, the per-test counter row in the sandbox setup, and the owner-role repo; §5 adds the adapter, counter name, and FGA client to the config override, the fake client, the store per test, and `drain_once/1`; §6 adds the committed-repo list with projection and latency cases, the latency measurement, the neutral fixture, Tier 2 as `Example.Scenarios`, the formatter, the skipped-scenario invariant, golden files instead of `mneme`; §7 has the per-thin-app jobs with the schema dump and statement diff and no tags job.
- `docs/code.md` (199 lines): v8 CODE revised. §2 adds the two-position `Decision`, the structs and behaviours the reference names, the `FactEvent` payload, and the configuration struct; §3 adds the hex pins with dates and the muontrap 2.0 note; §4 adds runtime-answered optional callbacks, fakes of the real type, capability records as clauses, and the `@after_compile` exhaustiveness check.
- `docs/writing.md`: the prose rules, with the no-em-dash rule, the one-word-per-concept rule, the v9 files in the Modes table, and document-specific rules for thin-app READMEs, the handoff, and the decision log.
- `CLAUDE.md`: read order, prose rules, placement rules, process rules from D47 to D49, and the prose gate command.
- References to the earlier implementation removed from `PLAN.md`, `docs/decisions.md` (D1, D33, D37, D40, D41, D43, D44 wording), `docs/reference.md` (§13 outbox sentence, §14 conformance table now lists modules and packages), and `docs/testing.md`. The owner asked for this on 2026-09-07; the rule now stands for every document.

## Gate

Prose gate over every document except this file, with the two lines that quote the banned words excluded:

```
grep -rniE "\b(simply|just|obviously|easy|easily|of course|basically|note that|in order to)\b|!|—" PLAN.md docs/testing.md docs/code.md docs/writing.md docs/reference.md docs/decisions.md CLAUDE.md | grep -v "docs/writing.md:.*Banned words\|CLAUDE.md:.*None of these words\|CLAUDE.md:.*grep -rniE" ; echo "exit=$?"
exit=1
```

Vocabulary leftovers:

```
grep -rniE "visibility-safe|compile-time binding|bound at compile time|erlang_28|postgresql 17|tags job|v10a|TURNSTILE_PROVIDER|Turnstile\.Provider" docs/testing.md docs/code.md docs/writing.md CLAUDE.md; echo "exit2=$?"
exit2=1
```

References to the earlier implementation:

```
grep -rniE "attempt[- ]1|ADR-|fac7683" PLAN.md CLAUDE.md docs/ | grep -v docs/handoff.md
(no output)
```

## Reference §14 check

Every claim in `docs/reference.md` §14 holds in `docs/testing.md`: the two roles and their names (§3 step 2); the sandboxed and committed databases and the three test repos with `Turnstile.TestRepos.Owner` as the owner-role repo (§3 step 4); `async: true` by default with `:committed` and `:tripwire` as the tagged exceptions (§6); shape tests on every pull request and benchmarks on demand (§6, §7); the committed-repo list item for item (§6); the neutral fixture and `priv/conformance/` per adapter (§6); `AdapterCase` binding through the override (§6); the four conformance modules (§6 names `Turnstile.Conformance.Case` and `AdapterCase`; the reader and the lint are `turnstile_assess`'s and appear in the `sources` job, §7); the schema dump and diff per thin app (§7 step 1).

## For the next agent

The writer of `docs/delivery.md`. Write it from D46 and `plan/review/delivery-plan.md` §1, with every gate as a command and its expected output. The gates the companions imply, per stage:

- **S0** (flake, ephemeral cluster, shared Cerbos and OpenFGA): `nix develop --command mix test` passes in `apps/turnstile_core` with the cluster starting and stopping; `nix develop --command cerbos --version` prints 0.55.0; `nix develop --command openfga version` prints 1.19.0; `nix run .#services` brings up Postgres, Cerbos, and OpenFGA and is stopped by hand. The S0 handoff records: every pin re-verified with where; whether Gatekeeper interfered with the Cerbos binary and what was done; the muontrap 2.0 `MuonTrap.Daemon` API as used. Nix is not installed on the development Mac; the agent stops and asks before running the installer.
- **S1** (frozen interfaces in core): `mix quality` in `apps/turnstile_core` green with the structs, behaviours, `Turnstile.Schema` macro, `%Turnstile.Config{}` schema, `Turnstile.Test.with_config/1,2`, `Turnstile.Test.Cluster.start/1`, `Turnstile.Test.Sandbox.setup/2`, the fake adapter, the in-memory ledger, and the scenario table in `docs/reference.md` §3a frozen. The S1 handoff cites the Elixir 1.20 changelog URL for the type-system claims in `docs/code.md` §1 and confirms `boundary` 0.10.4 compiles on 1.20.
- **S2a, S2b, S2c** (seam, `AdapterCase`, formatter): `mix quality` green; the seam sweep generated from `Repo.__info__(:functions)` passes; `AdapterCase` runs against the fake adapter; `mix test --formatter ExUnit.CLIFormatter --formatter Turnstile.Assess.Formatter` writes `tmp/results.json` with the fields in `docs/reference.md` §12; `mix turnstile.assess --check` fails on a results file with zero executed scenarios.
- **S3** (`turnstile_example` and `example_code`, ledger mode none): in `apps/example_code`, `mix test` runs `Example.Scenarios` with the seam enforcing, `EXAMPLE_LEDGER=none`; `mix turnstile.assess --check` passes; `mix turnstile.schema_dump` then `git diff --exit-code priv/schema/`.
- **S4** (`turnstile_code`): `AdapterCase` for `Turnstile.Code` green; `priv/conformance/` present; `example_code` Tier 2 executed count equals the scenario count minus declared skips.
- **S6** (`turnstile_ledger`): the interleaved-transactions case and lock-cost case on the committed repo; genesis, reconcile, replay, the catalog check, and the bulk API under `AdapterCase`'s fold-then-replay property.
- **S7** (`example_code` in mode Ecto): the `example_code` CI job as `docs/testing.md` §7 lists it, both ledger modes, `git diff --exit-code statement/statement.md`.
- **S8, S9, S10** (Postgres, Cerbos, OpenFGA: package then thin app): per package, `AdapterCase` green and `priv/conformance/` present; per thin app, the full CI job from `docs/testing.md` §7 including the schema dump and the statement diff. S10a first: `Turnstile.Fga.Client` and `Turnstile.Fga.Client.Fake`, the projector's unit tests against the fake; then the committed projection cases against `openfga run --datastore-engine memory`.
- **S11** (review, drift, replay per adapter): `mix turnstile.review` output for a date; the drift and replay scenarios in every thin app's executed count.
- **S12** (README, statement bodies, CI workflow): the workflow file with the `quality`, four thin-app, and `sources` jobs; the README's four statement bodies included by reference.

Each stage's handoff quotes the gate commands and output verbatim; the prose gate in `CLAUDE.md` runs on every changed document.

## Open

- The gate command in `CLAUDE.md` and in this file quotes characters the gate bans, so the lint excludes `docs/handoff.md` and the two lines in `CLAUDE.md` and `docs/writing.md` that list the banned words. `docs/delivery.md` should quote the command once and let `CLAUDE.md` be the source.
- `Example.Repo` and the web layer sit in the library app `turnstile_example` (D44); `docs/testing.md` §3 assumes it. If S3 cannot make that compile cleanly with a per-thin-app `config_path`, the fallback is each thin app owning its Repo and the contexts taking a repo argument, which changes D44, PLAN §Packages, and testing §3 step 4.
- `Turnstile.Test.Cluster.start/1` takes a `migrate:` function because core's `lib` depends on `ecto` alone and `ecto_sql` is test-only there; S1 confirms the dependency split works under `boundary` and the umbrella's shared `deps/`.
- The counter take on the Postgres dialect is one `UPDATE ... RETURNING` (reference §9); the shape count for a single-row fact write is therefore the re-read, the write, one ledger insert, and the counter take. Testing §6 counts the Postgres adapter's `set_config` statement as one query on top of that.
