# Relay glossary

The words `turnstile_relay` owns. A word with a second meaning elsewhere is listed in `docs/glossary-index.md` with the place each meaning lives.

| Term | Meaning |
|---|---|
| Runner | One named delivery loop: a process, a cursor row, and a lock, all under the name the application gave it |
| Job | What a runner delivers: where the rows are, what shipping a batch means, and what options it takes |
| Entry | One row on its way out: the position that orders it and the payload the job read |
| Position | The rising, unique number a job orders its rows by, a `bigserial` in the usual case |
| Payload | What the job read from its own table, carried to `deliver/3` and read by nothing here |
| Batch | The entries one pass reads and delivers together, at most as many as the runner's batch size |
| Pass | One transaction: take the lock, read above the cursor, deliver, advance the cursor, commit |
| Cursor | The position a runner has delivered to, one row per runner, advanced in the transaction that delivered |
| Lock | The transaction-scoped Postgres advisory lock a pass takes on the runner's name, asked for and never waited on |
| Stepping aside | What a pass does when another node holds the lock: report the cursor, deliver nothing, wait the idle interval |
| Wake-up | A cast from the process that wrote rows, cancelling the timer so the next pass runs at once |
| Idle interval | The wait before the next pass where the batch did not fill |
| Backoff | The wait before the pass that follows a failure, doubled once per failure in a row and capped |
| At-least-once | The guarantee: every row is delivered, and a row may be delivered more than once |
| Job case | The case template that holds a job to what a runner relies on, over a population module of the job's own |
