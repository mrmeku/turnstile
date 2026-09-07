# Handoff
*Mode: Reference. Written from scratch by the agent that wrote the v9 decision log; the next agent overwrites this file.*

## Task
Write `docs/decisions.md`, the decision log the next agent uses to revise the plan from v8 to v9, from the owner's answers, the review's holes, the repo lessons, the toolchain pins, and the delivery plan.

## Done
- `docs/decisions.md`: 49 entries in seven groups. Owner decisions D1 to D9 (Q1 to Q7 and Q10). Holes that block implementation D10 to D17. Holes that will cause rework D18 to D31. Clarity-only holes grouped in D32. Lessons from attempt 1 D33 to D41. Deferred list D42. Layout D43 (files), D44 (umbrella and migrations), D45 (the configuration struct), D46 (stages). Process D47 to D49 (Q8, Q9, the question-preamble rule).
- `docs/handoff.md`: this file.
- Nothing under `plan/` was modified.

## Gate
The banned-word grep from the task brief, run from the repo root over `docs/`: the case-insensitive search for the nine banned words, the exclamation mark, and the em dash, followed by `echo "exit=$?"`. The command itself cannot be quoted here without failing its own check.

Output:

```
exit=1
```

## For the next agent
Places where v8 contradicts itself, and how the log resolves each:
- PLAN §Packages "the adapter bound at compile time" and CODE §2 `Application.compile_env/3` against TESTING §6's four adapters in one `mix test`: resolved by the owner (D7), runtime binding through the config struct.
- PLAN §Adapters "every adapter's decision half is database-free" and REFERENCE §7 "one query" against REFERENCE §7's head stamp: resolved in D18; the head read is one counted query.
- REFERENCE §3 C12 "must be below" against REFERENCE §7 "reported, not bounded": resolved in D14; compared in the statement, never asserted.
- TESTING §5 "positions consumed in a rolled-back transaction are gaps" against the owner's gapless counter row: resolved in D6; rolled-back positions roll back with the transaction.
- CODE §4's process-dictionary rule against TESTING §5's config override: resolved in D32, two named uses.
- TESTING §7's `tags` job and `v0`…`v10b` list: moot under D3.
- `holes.md` cites paths relative to `new-plan/`, which no longer exists; every such path is `plan/v8/<file>`.

Calls I made that are mine, not the owner's, and would change the plan if reversed:
- D6's per-test named counter row. Without it, every sandboxed test that writes a fact holds the `default` row's lock until the test ends, and async Tier 2 serializes. The owner decided the counter row, not this mitigation.
- D44's placement of `Example.Repo`, the endpoint, and the web layer in the library app `turnstile_example`, configured by each thin app through its own `config_path`. The alternative (each thin app owns its Repo module) means the shared contexts need a repo parameter. I chose the library placement; the plan writer should keep whichever the S1 agent can make compile, and say which.
- D44's second Tier 2 job for `example_code` in ledger mode none, so mode none has a real run and not only Tier 1.
- D21 uses a catalog check rather than the hole's migration-helper refusal; D30 keeps three capability levels with a component name rather than adding a fourth level. Both say why in one sentence.
- D19 adds an after-compile assertion that core's overrides are the definitions in force; the hole asked only for the exhaustiveness check to move.

Things the plan writer must carry that are not decisions:
- The `Decision` struct in CODE §2's example has one `position` field; D18 and OPENFGA §7 need `head_position` and `applied_position`. Fix the example when porting CODE §2.
- REFERENCE section numbers are cited throughout the log (§3, §4, §6, §7, §8, §9, §10, §11, §12, §13). D43 asks docs/reference.md to keep them where the content survives; if a section is dropped, leave its number in place with a one-line pointer rather than renumbering.
- The prose rules ban the exclamation mark anywhere in `docs/`, so bang-named functions cannot be spelled in these files; write "the bang variant" or name the module.

## Open
- `attempt-1` is a branch at `0f4888b`, not the tag Q1 asked for. D1 has the S0 agent create the tag and remove the branch; the owner has not said whether removing the branch is acceptable.
- Whether the per-test named counter row (D6) is acceptable to the owner, or whether Tier 2 should accept serialization on the `default` row.
- Whether mode none needs the second `example_code` Tier 2 job (D44) or Tier 1 alone is enough evidence for the statement's mode-none claims.
- Where COMPANION Appendix A's terms live before any package glossary exists; D43 says docs/reference.md §12 for now, which stretches that section.
- The delivery plan's S0 gate expects `cerbos --version` from a fetched binary; nobody has verified the Darwin arm64 tarball runs unsigned on macOS without a Gatekeeper prompt.
