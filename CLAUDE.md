# Turnstile: working rules for agents

## Read first

`PLAN.md`, then `docs/writing.md`, `docs/reference.md`, `docs/testing.md`, and `docs/code.md`, in that order, before starting any stage. `docs/delivery.md` names the stages and their gates.

## Prose

Sentence-case headings. None of these words: *simply, just, obviously, easy, easily, of course, basically, note that, in order to*. No exclamation marks. No em-dashes. `docs/writing.md` has the rest.

## Placement

- A package's concepts appear only in that package's directory. Adapter packages are domain-free: no adapter names a Document, a Marking, or a rule id from the example.
- Capability declarations per rule live in the thin apps (`apps/example_<adapter>/`), never in an adapter package.
- Library packages ship migration helpers. Migrations exist only in the thin apps, one set each.
- Adapters own mechanism. No sentence in an adapter's docs tells the application what it may do.
- Test names are scenario ids and sentences from `docs/reference.md` §1 and §3a.
- `warnings_as_errors: true` everywhere.
- Pin every external version and say where you verified it. Do not guess a version.

## Process

- Stages run one at a time, on `main`, no worktrees, in the order `docs/delivery.md` §4 gives.
- Each stage ends with its gate from `docs/delivery.md` run and passing, then one or more commits, unsigned: `git -c commit.gpgsign=false commit`. One idea per commit. The last commit message quotes the gate's output and records what `docs/delivery.md` asks the stage to record.
- The prose gate, run on every changed document, must print `exit=1`:

```
grep -rniE "\b(simply|just|obviously|easy|easily|of course|basically|note that|in order to)\b|!|—" <files> ; echo "exit=$?"
```

- A question to the owner carries a plain-language preamble inside the question text itself, before the question and its choices: what the thing is, why it matters, what each choice costs. Prose written outside the question is not seen.
