# Writing
*How prose and code are written in this repository. Nothing here is original: each rule names the guide it is taken from, so a reviewer can go to the source when this page is not enough.*

## Sources

| Guide | What it governs here |
|---|---|
| Google developer documentation style guide, https://developers.google.com/style | Tone and mechanics of all prose: voice, tense, headings, word choice. |
| Microsoft Writing Style Guide, https://learn.microsoft.com/style-guide | The register for explanatory prose: warm, direct, "bigger ideas, fewer words". |
| Elixir, *Writing documentation*, https://hexdocs.pm/elixir/writing-documentation.html | `@moduledoc`, `@doc`, doctests; documentation is for users, comments are for maintainers. |
| Elixir Style Guide, https://github.com/christopheradams/elixir_style_guide | Naming, layout, and the shape of code. Enforced by Credo. |
| *Art of README*, https://github.com/hackergrrl/art-of-readme | What the README is for and what it must not become. |
| Minto, *The Pyramid Principle* | The shape of an explanation: claim first, then support. |

## Two registers

The repository has two registers, and the difference is deliberate.

**Prose that explains**, which is `PLAN.md`, the adapter notes in `docs/reference.md` §4, and each thin app's README, is *informative*: it states the problem before the mechanism, names the idea after showing it, says why the alternative was not taken, and links the source. Full sentences; a paragraph may hold one idea and its consequence. This register follows Microsoft's advice to write the way an expert would explain something across a table.

**Code and reference**, which is modules, functions, glossaries, the scenario tables, callback specs, and the companions under `docs/`, is *terse*: it states what a thing is and when to use it, and stops. No narrative, no motivation, no history. If a reader needs the why, the doc links to the prose that has it. This register follows Elixir's documentation guide: the first sentence of a `@moduledoc` or `@doc` is a summary that stands alone, and everything else is example or constraint.

A reader should be able to tell which register they are in from the first line.

## Prose rules (Google, Microsoft)

- **Active voice, present tense.** "The projector derives tuples", not "tuples are derived by the projector".
- **Second person in how-to and tutorial; impersonal in reference; "we" in explanation.** Never "the user" when "you" is meant.
- **Sentence-case headings.** "Choosing an adapter", not "Choosing An Adapter".
- **Define before use.** A term appears in a glossary before it appears in prose, or is defined in the sentence that introduces it.
- **One idea per paragraph; the consequence of that idea may share it.**
- **Banned words:** *simply, just, obviously, easy, easily, of course, basically, note that, in order to.* They tell a struggling reader the problem is them, or add nothing. Linted by the gate in `CLAUDE.md`.
- **No exclamation marks in prose.**
- **No em-dashes.** A comma, a colon, or a new sentence does the work. Linted with the banned words, because the character is the same in every file.
- **A concept that belongs to someone else gets two sentences in our words and a link.** Never a section.
- **Introducing an idiom: show it in use, name it, contrast it with what it replaces, link its source.** Never name first.
- **One word per concept.** "Adapter", never "provider", for the pluggable mechanism; "subject", "object", "operation", "environment" from NIST SP 800-162 for the port's vocabulary; a second word for the same thing is a lint failure once the glossary exists.
- **The repository informs; it does not assign.** No exercises, quizzes, or homework.

## Code rules (Elixir documentation guide, Elixir Style Guide)

- **`@moduledoc`**: first sentence is a one-line summary that stands alone in a module list. Second paragraph, if any: when to use this module and what it is not. No history, no rationale; link the document that has it.
- **`@doc`**: first sentence states what the function returns or does, in the third person ("Returns…", "Derives…"). Then arguments that need explanation, then an example as a doctest where one is meaningful. Options are documented as a list under `## Options`.
- **Doctests over prose examples.** An example that cannot run is a claim, not an example.
- **Comments explain why, never what.** A comment that restates the next line is deleted. A comment that says why the next line is surprising is kept.
- **Names come from the glossary of the package's context.** A function in `turnstile_fga` says *tuple*; one in `turnstile_example` says *Document*. An adapter package never names a thing from the example's domain; the thin app's translation table is where the two vocabularies meet.
- **Specs on every public function; `@typedoc` on every public type.** The spec is part of the documentation, not a substitute for it.
- **Layout and naming per the Elixir Style Guide; Credo enforces it.** Nothing here restates that guide; `docs/code.md` §4 lists what this repository adds.
- **Test names are scenario ids and sentences.** In Tier 2, `scenario "enf-01", "<sentence>"` with the id and sentence from `docs/reference.md` §3a. In Tier 1, the property's law in one sentence. A test name a 3PAO could not read is renamed.

## Document-specific rules

- **README** (Art of README): purpose in one paragraph, the four statements side by side, a quickstart that runs, links. It summarizes; it is never the source of anything.
- **Thin-app README** (how-to): what this adapter costs, as the directory's contents explained in order: the binding, the migrations, the policies or model, the capability declaration; then the translation table between the example's words and the adapter's; then where the statement is and how it is regenerated.
- **Adapter notes** (`docs/reference.md` §4, and later each adapter package's README): mechanism per rule shape, what the adapter declares, its inventory item, its measured latency and components. No sentence tells the application what it may do.
- **Glossaries** (reference): term, meaning, nothing else. A term's history belongs in `PLAN.md`, if anywhere.

## Review checklist

1. Register matches: teaching prose is informative; code and reference are terse.
2. No banned words; no exclamation marks; no em-dashes; headings in sentence case.
3. Every term used is in the context's glossary or defined on first use; one word per concept.
4. Foreign concepts get two sentences and a link, not a section.
5. Idioms are shown before they are named.
6. Every external version is pinned and says where it was verified.
