# Handoff
*Mode: Reference. Written from scratch by the agent that finished the last task; the next agent reads it before starting.*

## Task

Write `docs/delivery.md` from D46 and `plan/review/delivery-plan.md` §1: every stage with the decisions it implements, its deliverables, and its gate as a command and its expected output. This is the last document before the owner's checkpoint ⟨D48⟩.

## Done

- `docs/delivery.md` (346 lines, How-to): §1 the checkpoint; §2 how a stage runs, replacing the worktree discipline ⟨D47⟩; §3 the stages S0, S1, S2a, S2b, S2c, S4, S3, S6, S7, S8a, S8b, S9a, S9b, S10a, S10b, S10c, S11, S12, each with entry, decisions implemented, deliverables, gate, and what its handoff records; §4 the order; §5 the deferred items ⟨D42⟩.
- `docs/writing.md` Modes table: `docs/delivery.md` moved from the Reference row to the How-to row, matching D43.
- The word "ported" removed from `PLAN.md` §Phases, `docs/reference.md` §3a and the §14 heading, and D46, since it pointed at history the documents no longer name.

## Gate

```
grep -rniE "\b(simply|just|obviously|easy|easily|of course|basically|note that|in order to)\b|!|—" PLAN.md docs/testing.md docs/code.md docs/writing.md docs/reference.md docs/decisions.md docs/delivery.md CLAUDE.md | grep -v "docs/writing.md:.*Banned words\|CLAUDE.md:.*None of these words\|CLAUDE.md:.*grep -rniE" ; echo "exit=$?"
exit=1
grep -rniE "attempt[- ]1|ADR-|fac7683" PLAN.md CLAUDE.md docs/ | grep -v docs/handoff.md; echo "exit2=$?"
exit2=1
grep -rn "ported" PLAN.md docs/ CLAUDE.md | grep -v "reported\|imported\|supported\|Supported\|exported"; echo "leftover=$?"
leftover=1
```

Names checked against the companions: `Turnstile.Test.Cerbos.start_shared/1` (`docs/testing.md` §4); `mix turnstile.schema_dump` as a task in `turnstile_ledger` (§7); the scenario ids `enf-01`, `rev-01`, `rev-06`, `rvw-04`, `inv-02` in `docs/reference.md` §3a; the config fields `batch_ids_cap` and `adapter_options` in `docs/code.md` §2.

## For the next agent

There is no next agent until the owner has read `PLAN.md` and the six companions and approved or edited them ⟨D48⟩. After that, the next task is S0 in `docs/delivery.md` §3. Its agent needs to know:

- Nix is not installed on the development Mac (arm64, Docker present, Docker not to be used). Stop and ask, with a plain-language preamble inside the question, before running the installer; it needs the owner's password.
- `mix turnstile.schema_dump` lives in `turnstile_ledger` from S1, not S6, because S3's gate dumps `example_code`'s schema before the ledger exists.
- S4 runs before S3. The stage numbers are D46's; the order is `docs/delivery.md` §4.
- S0 creates the umbrella root and `apps/turnstile_core` with test support only; S1 adds the library modules.

## Open

- The order S4 before S3 is a reading of D46, which says "in sequence" and lists S3 before S4 while making `example_code` bind `turnstile_code`. If the owner prefers S3 first, `example_code` would need to bind `Turnstile.Adapter.Fake` for one stage, and D46 gets a superseding entry either way.
- `Example.Repo` sits in the library app `turnstile_example` ⟨D44⟩; S3's handoff reports whether it compiles cleanly under a per-thin-app `config_path`, and the fallback is each thin app owning its Repo with the contexts taking a repo argument.
- Whether Gatekeeper interferes with the fetched Cerbos binary on Darwin is unknown until S0 runs it.
- `Example.User` carries no fact fields and is unprotected as an object; the scenario table has no scenario against it. Unchanged from the previous handoff.
- `docs/reference.md` §3a still describes the scenario macro as `scenario/4`; `docs/testing.md` §6 writes it with `control:` and `rule:` options plus a block, which is arity 4 counting the block. Consistent, but S1 should confirm the arity when it writes the stub.
