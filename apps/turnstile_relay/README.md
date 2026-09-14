# Turnstile relay

Batched, ordered delivery from a Postgres table: `Turnstile.Relay`. One runner per job, a cursor that says how far that runner has got, a wake-up for the process that wrote a row, and an advisory lock so a second node steps aside rather than shipping the same rows twice.

This package holds no authorization concept. It names no subject, no object, and no rule, and its `lib` takes none of the library's other packages. What it knows is that rows arrive in a table, that something slow has to be told about them in order, and that the telling can fail.

- `Turnstile.Relay`: the supervisor, `wake/1`, `drain_once/1`, and `options_schema/0`. An application puts `{Turnstile.Relay, runners: [[name: :markers, repo: MyApp.Repo, job: MyApp.Markers]]}` in its tree and calls `wake/1` after the write that produced rows. A test calls `drain_once/1` and starts nothing.
- `Turnstile.Relay.Job`: the behaviour. `read/4` answers the entries above a position, in position order, at most a limit of them; `deliver/3` ships one batch; `options_schema/0` says what the job's own options are. Both run inside the pass's transaction, so a job that reads through the runner's repo reads on the connection the cursor advances on.
- `Turnstile.Relay.Entry`: one row on its way out, a position and a payload. What a payload holds is the job's, and nothing here reads it.
- `Turnstile.Relay.Pass`: what one pass did. Whether it held the lock, how many entries left, where the cursor stands, whether the batch filled, and the moment it finished, taken from the clock the runner was configured with.
- `Turnstile.Relay.Cursor` and `Turnstile.Relay.Migration`: how far a runner has delivered, one row per runner, and the helper an application's own migration calls to create that table. A runner no row names stands at zero, which is below every position, so a first pass reads from the start.
- `Turnstile.Relay.JobCase`: the case template a job is proved by, over a `Turnstile.Relay.JobCase.Rows` module that writes the population. A job outside this repository points the template at its own table and runs the same three obligations.

`glossary.md` defines the words this package owns. Its `lib` depends on `ecto`, `ecto_sql`, `nimble_options`, and `telemetry`; `postgrex` is there because an adopter's repo is a Postgres one and the advisory lock is Postgres's. The test run adds `turnstile`, for the ephemeral cluster and the repos it starts, and `stream_data` for the durability property.

## One pass

A pass is one transaction:

1. Ask for the advisory lock on the runner's name. A runner told no reports the cursor, delivers nothing, and tries again after its idle interval.
2. Read the cursor, then read a batch above it through the job.
3. Deliver the batch through the job.
4. Advance the cursor to the position of the last entry delivered.
5. Commit.

Delivery that fails rolls the pass back. The cursor stays where it was, so the same batch is read again on the next pass. That is at-least-once delivery in position order, and a job's `deliver/3` is written for a batch it may have seen before: a row keyed at the far end, an upsert, or a request the far end treats as repeatable.

The lock is transaction-scoped, so a node that stops holds nothing, and it is asked for rather than waited on: a runner that finds another node delivering has nothing useful to do with the wait.

## What the runner decides

Nothing about the rows. It decides when the next pass runs: at once where the batch filled, since the rows behind a full batch are already waiting; after the idle interval where it did not; and after a growing wait, doubled per failure and capped, where the pass failed. One pass that worked puts the count of failures back to zero.

A wake-up is a cast, so the process that wrote the rows is not held up by a delivery. It cancels the timer and passes at once. A wake-up that arrives while a pass is already pending is dropped, because that pass reads everything committed before it runs, which is everything the wake-up is about.

## What an application supplies

A repo, a job, and a name. The name is the row the cursor is kept in, the pair the advisory lock is taken on, and, unless the options say otherwise, what the runner's process is registered under.

The repo is one whose calls carry no decision: a plain Ecto repo, or a repo the library's seam knows as the owner's. A cursor states nothing about a subject or an object, so there is nothing for a decision to cover, and where the rows a job reads may be placed is the application's own rule to make.

The clock is an option. A pass reads the moment it finished from it once the transaction has returned, so a test reads its own time and nothing here asks the system for one.

## Telemetry

Every pass emits `[:turnstile, :relay, :pass]`, whether it delivered, stepped aside, or failed: measurements `delivered` and, where there was one, `position`; metadata the runner's `name`, its `job`, and either the `%Turnstile.Relay.Pass{}` or the `error` term the job reported.
