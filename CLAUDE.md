# Turnstile: working rules for agents

## Read first

`PLAN.md`, then `docs/writing.md`, `docs/reference.md`, `docs/testing.md`, `docs/code.md`, `docs/decisions.md`, and `docs/handoff.md`, in that order, before starting any task. `docs/delivery.md` names the stages and their gates.

## Prose

One Diátaxis mode per file, declared on line two in italics. Sentence-case headings. None of these words: *simply, just, obviously, easy, easily, of course, basically, note that, in order to*. No exclamation marks. No em-dashes. `docs/writing.md` has the rest.

## Placement

- A package's concepts appear only in that package's directory. Adapter packages are domain-free: no adapter names a Document, a Marking, or a rule id from the example.
- Capability declarations per rule live in the thin apps (`apps/example_<adapter>/`), never in an adapter package.
- Library packages ship migration helpers. Migrations exist only in the thin apps, one set each.
- Adapters own mechanism. No sentence in an adapter's docs tells the application what it may do.
- Test names are scenario ids and sentences from `docs/reference.md` §1 and §3a.
- `warnings_as_errors: true` everywhere.
- Pin every external version and say where you verified it. Do not guess a version.

## Process

- Tasks run one at a time, on `main`, no worktrees. Each task goes to a fresh context that reads the files above and nothing it does not need.
- Each task ends with its stage gate from `docs/delivery.md` run and passing, then one or more commits by the agent that did the work, unsigned: `git -c commit.gpgsign=false commit`. One idea per commit.
- Every task writes `docs/handoff.md` from scratch in its last commit, never revising the previous one. Sections: **Task**, **Done**, **Gate** (the commands and their output, verbatim), **For the next agent**, **Open**. The orchestrator reads that file and the gate output to choose the next task.
- The prose gate, run on every changed document except `docs/handoff.md`, must print `exit=1`:

```
grep -rniE "\b(simply|just|obviously|easy|easily|of course|basically|note that|in order to)\b|!|—" <files> ; echo "exit=$?"
```

- A question to the owner carries a plain-language preamble inside the question text itself, before the question and its choices: what the thing is, why it matters, what each choice costs. Prose written outside the question is not seen.
