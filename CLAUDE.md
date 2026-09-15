# Turnstile: working rules for agents

## Read first

`README.md`, then `docs/design.md`, `docs/requirements.md`, `docs/conformance.md`, `docs/events.md`, and `docs/contributing.md`, in that order, before starting any stage. `docs/contributing.md` says how a stage runs, what it records, and which gate each package passes.

## Prose

Sentence-case headings. None of these words: *simply, just, obviously, easy, easily, of course, basically, note that, in order to*. No exclamation marks. No em-dashes. `docs/contributing.md` §4 has the rest.

## Placement

- A package's concepts appear only in that package's directory. Adapter packages are domain-free: no adapter names a Document, a Marking, or a rule id from the example.
- Before adding a module, ask in order: Is it named by a consumer of a published package? The root of `lib/`. Does it touch the world, or exist because of how another system works? `infrastructure/`. Does it orchestrate a use case? `application/`. Otherwise `domain/`. Calls run one way: the root reaches `application/`, `infrastructure/`, and `domain/`; `application/` reaches `infrastructure/` and `domain/`; `infrastructure/` reaches `domain/`. `docs/design.md` §6 has the table.
- What each rule of the example is enforced by is stated in the thin apps (`apps/example_<adapter>/`), never in an adapter package.
- Library packages ship migration helpers. Migrations exist only in the thin apps, one set each.
- Adapters own mechanism. No sentence in an adapter's docs tells the application what it may do.
- Test names are law ids and sentences from `docs/conformance.md` §2, or scenario ids and sentences from `docs/example.md` §4.
- `warnings_as_errors: true` everywhere.
- Pin every external version and say where you verified it. Do not guess a version.

## Process

- Stages run one at a time, on `main`, no worktrees, by the steps `docs/contributing.md` §5 gives.
- Each stage ends with its gate from `docs/contributing.md` §5 run and passing, then one or more commits, unsigned: `git -c commit.gpgsign=false commit`. One idea per commit. The last commit message quotes the gate's output and records what `docs/contributing.md` §5 asks the stage to record.
- The prose gate, run on every changed document, must print `exit=1`. `docs/contributing.md` §4 is the one exception, because it is where the banned words are listed:

```
grep -rniE "\b(simply|just|obviously|easy|easily|of course|basically|note that|in order to)\b|!|—" <files> ; echo "exit=$?"
```

- A question to the owner carries a plain-language preamble inside the question text itself, before the question and its choices: what the thing is, why it matters, what each choice costs. Prose written outside the question is not seen.
