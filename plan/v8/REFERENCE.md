# Turnstile — reference notes for plan v8
*Mode: Reference. Tables, numbers, and mechanics the plan cites by section. Nothing here is a decision the plan does not already make; this is where the plan's decisions are spelled out at implementation grain. Each section moves into the docs of the package that owns it as that package appears. ⟨verify⟩ marks a claim to check against the pinned sources or the pinned Ecto before relying on it.*

## §1 Requirement groups → controls

Enhancement membership in the FedRAMP Rev 5 Moderate profile is ⟨verify⟩; the lint checks it permanently against the pinned profile. Beyond-baseline citations are allowed and marked. KSI ids are read from the pinned 20x docs; the family names below are orientation only.

| Group | Moderate baseline controls | Beyond baseline (cited, marked) | 20x family |
|---|---|---|---|
| Enforcement | AC-3 | AC-25 always invoked; AC-3(7) role-based | KSI-IAM |
| Least privilege | AC-6, AC-6(1), (2), (5), (9), (10); AC-2(7) | | KSI-IAM |
| Separation of duties | AC-5 | | KSI-IAM |
| Revocation and expiry | AC-2, AC-2(1), (2), (3); PS-4, PS-5 | AC-3(8) revocation of authorizations; AC-16 security attributes | KSI-IAM |
| Decision audit | AU-2, AU-3, AU-3(1), AU-12, AC-2(4); AU-9, AU-9(4), AU-11 | | KSI-MLA |
| Access review | AC-2 account review; AC-6(7) | | KSI-IAM |
| Re-authentication | IA-11 | | KSI-IAM |
| Emergency override | AC-6(9), AC-2(2), AU-6 | | KSI-IAM, KSI-MLA |
| Change control on policy | CM-3, CM-5 | | KSI-CMT |
| Inventory | CM-8 | | KSI-PIY |

Notes.
- AU-2: the FedRAMP-assigned parameter names, for web applications, authorization checks, data access, data changes, and permission changes among the events to log ⟨verify Rev 5 wording⟩. "Every call is evented" is that parameter, met; the statement cites it.
- Change control is a strength to show: for rules in code and Postgres a policy version is a commit and a deploy, so review is approval; the scenario asserts every policy-version event names its author and its approval.
- Tenant isolation: SSPs answer the multi-tenant separation question under AC-3 and SC-4/SC-7; the C13 scenario across agencies is where it is proven.
- Training (AT-3) and CUI marking rules (32 CFR 2002) are organization-level; origination defaults to Service Provider Corporate.

## §2 Dissemination controls

A category says what the information is; a control says who may not receive it, below the default that anyone with a lawful government purpose may. The Registry allows a fixed set; a document may carry several; all must hold. Four modeled, one per shape of subject test; FEDCON, NOCON, DISPLAY ONLY, and the attorney markings are the same shapes with other values.

| Control | Registry marking | Test on the subject |
|---|---|---|
| `federal_only` | FED ONLY | employment is federal |
| `no_foreign` | NOFORN | nationality matches the designating agency's |
| `named_list` | DL ONLY | the subject is on the marking's list — a per-object grant |
| `releasable_to` | REL TO | nationality is in the marking's country list |

## §3 Rules (moves to the example's glossary in Phase 2)

| Rule | Statement |
|---|---|
| **C1 Lawful purpose** | `read` on a Document requires an Assignment to its Program or an OfficeRole in its designating Office. |
| **C2 Controls, all of** | Every Control on the effective marking is a test on the subject, and all must pass. |
| **C3 Specified categories** | A Specified category adds its implied Controls. Effective controls are declared ∪ implied. Nothing is copied. |
| **C4 Banner** | With portion marking, a Document's marking is the union of its Portions'. ⟨open 1⟩ |
| **C5 Decontrol** | After the decontrol date or event, C2–C4 no longer apply; C1 still does. The current time is a port-supplied environment fact. |
| **C6 Named list is a direct grant** | `named_list` membership is per Document per User and combines with nothing; it never overrides C1. |
| **C7 Marking gates** | Changing a marking, setting a decontrol, or decontrolling requires a `designator` role in the designating Office. |
| **C8 Re-authentication** | C7 operations additionally require the session to have re-authenticated within a configured window. |
| **C9 Separation of duties** | A marking change proposed by one designator must be approved by a different approver. |
| **C10 Audited override** | A privileged user holding the override permission may read a Document outside C1 with a justification; the read succeeds, always emits its own event, and is reported to the designating Office. Never unconditional. |
| **C11 Continuous evaluation** | Assignments, list membership, employment, and nationality are evaluated at every check; a change deletes nothing. |
| **C12 Revocation clock** | A revoked fact is enforced within the configured maximum delay; the adapter's measured revocation latency must be below it. |
| **C13 Scope fidelity** | `scope` returns exactly the rows for which `check` is true. |

Where the adapters differ on these: write gates without application code — Postgres only, a C7-violating marking change is refused by the database whether or not the application asked; rules owned by non-developers, versioned and tested as their own artifact — Cerbos only; explanation — Cerbos names the matched rule, code names the clause, Postgres names nothing; derived markings (C3, C4) — Cerbos plans `scope` only over attributes it is sent, so effective controls are materialized per Document or `scope` falls back to `filter` and records limited; request-time facts (C5, C8) — native everywhere, Postgres threads them through session settings, OpenFGA takes C5 as a tuple condition with the time in the check context and takes C8 in the adapter, from the environment, before the call. OpenFGA alone: C3 and C4 are tuple-to-userset with nothing copied; C9 is `approver from office but not proposer`; explanation is the path from `Expand`; `scope` is `ListObjects`, capped, declared limited; write gates unsupported. The model and the tuple mapping are in `OPENFGA.md`.

## §4 Adapters: comparison and notes

| Adapter | Package | Enforcement | Explains | Revocation latency | Rules live in | Boundary cost |
|---|---|---|---|---|---|---|
| Rules in code | `turnstile_code` | the application's discipline, backed by the seam | the clause | one request | Elixir modules; a deploy is a policy version | none |
| Postgres row-level security | `turnstile_postgres` | the database; write gates need no application code | verdict only | one transaction | migrations; a migration is a policy version | none new |
| Cerbos | `turnstile_cerbos` | the application's discipline; policies versioned and tested as their own artifact | verdict and matched rule | one request for facts; the policy poll interval for rules | policy files; a policy owner | one sidecar |
| OpenFGA | `turnstile_fga` | the application's discipline, backed by the seam; the graph decides | the path (`Expand`) | commit + drain + write + check-cache TTL for facts; model publication for rules | a model file in a repository, published as an immutable model id; tuples projected from the ledger | a server and a datastore — two inventory items, one engine if the datastore shares the application's Postgres instance |

Declarations, the same for every adapter: capability per scenario (native, limited, unsupported); default origination profile; parameters exposed; inventory item (name, version, where it runs, its log location — for the Integrated Inventory Workbook, CM-8); measured revocation latency.

- **Postgres.** The application role must not own the tables, or row-level security is bypassed; `FORCE ROW LEVEL SECURITY` on every protected table; session settings set inside each transaction (`SET LOCAL`, read with `current_setting`), because pools reuse connections; reads from a replica add replica lag to revocation latency and the adapter measures it. The policy expressions are read back from `pg_policy` for the policy-version event. Replay for this adapter means state and policies in a scratch database; Phase 5.
- **Cerbos.** Facts arrive with each request, so their latency is one request; rules arrive on the sidecar's policy poll interval, which is the latency for policy changes. A sidecar picking a version up is measured as propagation latency, not ledgered. The sidecar's decision logs are reconciled with the port's decision events; any difference is a drift scenario. Its `version` field on a policy runs variants side by side and is not history; history is the policy repository's commit. Replay is the cheapest of the three: fold facts to the date, check out the policies at the commit, start a throwaway sidecar.
- **Rules in code.** The role→permission table is declared data; attribute predicates are functions in the same modules. Replay of the predicates needs the commit; the statement says replay of code rules depends on the repository's retention.
- **OpenFGA.** Requires a ledger: the projector drains fact events from the visibility-safe reader from a checkpoint, applies the tuple mapping, writes in batches (default `maxTuplesPerWrite` 100 ⟨verify⟩), advances the checkpoint in the application's database. Writes are not idempotent — an existing tuple rejects a write and a missing one rejects a delete — so the drain reads first or tolerates exactly those errors, and a re-drain after a crash must converge (a Tier 1 case). `rebuild/1` is genesis for the graph: fold from zero, write everything; minutes for a million facts, offline. Reconcile compares the fold with `Read`, paged by type; cost is proportional to tuples, so the interval is longer and printed. `Check` pins the model id and sets `consistency` per operation — `HIGHER_CONSISTENCY` under C7–C10, `MINIMIZE_LATENCY` allowed for reads, a printed parameter; the check cache, if enabled, adds its TTL to latency. `ListObjects` has a configurable result cap and deadline on the order of a thousand ⟨verify⟩; above it the seam falls back to `filter` per page with `BatchCheck`. Self-hosted means the open-source server; a hosted FGA is a hosted engine and inadmissible. Replay: fold to the date, write the tuples into a throwaway server with the in-memory datastore, pin the model in force then — models are immutable and kept — and `Check`.

## §5 Policy-version events

Shape, for every adapter: adapter, version identifier, content hash, when, author or approval. Content by value only when it is text under `policy_content_cap` (64 KB default); above it, or for anything not text, a hash and a pointer into the store, and the statement prints which. Decision records carry the version identifier and never content. One event per version — never per node, boot, or sidecar.

| Adapter | Version | Appended by | Carries | Getting an old version back |
|---|---|---|---|---|
| Rules in code | the commit or release | the application at boot, only when the ledger head names an older version | commit, hash of the rule modules, the role→permission table as data when under the cap | check out the commit; run that release's port |
| Postgres | the migration number | the migration, in the same transaction as its DDL | `USING` and `WITH CHECK` expressions read from `pg_policy` — self-contained | apply that migration's policies to a scratch database |
| Cerbos | the policy repository's commit | the policy repository's CI on merge | commit, hash of the files, the files when under the cap | a throwaway sidecar over the files at that commit |
| OpenFGA | the model id the server returns on publish, with the model repository's commit | the model repository's CI on publish | model id, commit, hash of the model file, the DSL text when under the cap | pin the model id — models are immutable and kept — over tuples folded to the date in a throwaway server |

## §6 The Repo seam: surface, mechanics, checks

`use Turnstile.Repo` after `use Ecto.Repo`; the macro raises at compile time if the order is wrong. The failure mode to defend against is silent: a function core forgot to wrap runs unmediated.

**Classification** (`Turnstile.Repo.Surface`), every `Ecto.Repo` function in exactly one bucket:
- *query* — mediated through `prepare_query/3`: `all`, `one`, `one!`, `get`, `get!`, `get_by`, `get_by!`, `reload`, `reload!`, `aggregate/3` and `/4`, `exists?`, `stream`, `preload`, `update_all`, `delete_all`.
- *write* — overridden: `insert`, `insert!`, `update`, `update!`, `delete`, `delete!`, `insert_or_update`, `insert_or_update!`, `insert_all`.
- *raw* — wrapped to demand an exemption: `query`, `query!`, `query_many`, `query_many!`.
- *plumbing* — touches no rows: `transaction`, `rollback`, `in_transaction?`, `checkout`, `checked_out?`, `config`, `start_link`, `stop`, `child_spec`, `load`, `get_dynamic_repo`, `put_dynamic_repo`, `default_options`, `prepare_query`, `to_sql`, `explain`, `disconnect_all`, `__adapter__`.

**Exhaustiveness at compile time.** In a `@before_compile` hook core reads the module's actual public functions with `Module.definitions_in/1` and fails compilation on any name and arity it has not classified — including the shorter arities default arguments generate, functions the adapter injects, and the reduced surface of a `read_only` repo. Core pins `ecto` to the minor range the classification was written against.

**Injected last.** Overrides and core's `prepare_query/3` are defined in that same hook with `defoverridable` and `super`, so they wrap whatever the application or adapter defined; an application's own tenancy `prepare_query` runs inside ours. Overrides redeclare the default argument (`opts \\ []`) so every arity routes through them. ⟨verify⟩ hook ordering against the adapter's own `@before_compile` on the pinned Ecto: Tier 1 has a case that `query/3` refuses without an exemption; if ordering defeats the wrap on some adapter, the raw bucket falls to the static check alone and the statement says so.

**Proof at runtime.** A Tier 1 sweep generated from `Repo.__info__(:functions)` calls every non-plumbing function with a fixture and no decision and asserts refusal. Explicit cases: `preload`, `aggregate`, `exists?`, `stream`, `reload`, `insert_all` with entries and with a query source, and an `Ecto.Multi` run through `transaction`. ⟨verify⟩ that `prepare_query/3` fires for the queries `preload` generates on the pinned Ecto; the case settles it.

**Static checks**, shipped in core, advisory in the statement: `Turnstile.Credo.NoRawSQL` flags `Ecto.Adapters.SQL.query*` and `Postgrex.*` calls outside an allowlist (migrations, reconcile, the ledger's own code); `Turnstile.Credo.UnmediatedRepo` flags any `use Ecto.Repo` without `use Turnstile.Repo`. Nothing else: a check that every Repo call carries options is the rejected compile-time heuristic reborn; module-dependency boundaries are `boundary`'s job, which core uses for its own top layer.

**Statement prints:** the classification with counts, the Ecto version, a hash of the surface, the exemption list with reasons, the static-check results.

## §7 Audit records: shapes, span, caps, sizes, shape tests

**Shapes.**
- `authorize`, `check`: one record per object — subject, object type and id, operation, verdict, reason.
- `batch`, `filter`: one record for N objects with N verdicts; ids listed up to `batch_ids_cap`, beyond it a count and a SHA-256 of the sorted ids.
- `scope`: one record with the object type, the operation, and the enforced rule — the inspected `dynamic`, truncated at `rule_cap` with a hash of the full text, parameter lists longer than `batch_ids_cap` elided to a count and hash — plus ledger position and policy version.
- `review`: one record per review.
- Common fields (AU-3, AU-3(1)): type, time, source component, outcome, subject identity, request or session id, adapter, policy version, `head_position` and `applied_position` (equal unless the adapter projects), `operation_id`. No attribute values by default.

**Span.** `:start` — the decision, with its ledger position. `:stop` — rows returned, rows affected, `operation_id`, duration, and for bulk fact writes the minimum and maximum ledger positions. `:exception` — the failure. The position is stamped at decision time; the query runs in the same request; a `dynamic` built from prefetched subject attributes is as fresh as the decision, one built on subqueries is as fresh as execution; either gap is inside measured revocation latency; RLS evaluates at execution.

**Settings and caps**, printed in the statement: `decision_volume` — `:all` (default) or `:denials_writes_privileged`; denials, writes, and privileged operations are never sampled. `batch_ids_cap` 1,000. `rule_cap` 4 KB. `policy_content_cap` 64 KB. `fact_insert_batch` — a dialect default (§11).

**Sizes to plan against.**
- A decision record is 300–600 bytes. At `:all`, 1,000 port calls per second is about 86 million records a day, tens of gigabytes uncompressed — a log-pipeline sizing question, and why `decision_volume` exists.
- A fact event row is 200–400 bytes; a million fact changes a year is a few hundred megabytes. Retention is the life of the system; partition by position range if growth demands it — the read-from-position contract does not care.

**Shape tests**, in Tier 1, every pull request, cited by nothing. They assert counts — queries issued (from Ecto's `[:repo, :query]` telemetry, transaction-control statements filtered out), audit records emitted, ledger rows written — because every regression that matters changes a number: per-row inserts instead of batches, per-row telemetry, a forgotten no-op filter, `RETURNING` on a non-fact write, a per-row `check` inside `scope`. Counts are deterministic; timings measure the runner. Fixtures are small: the only size that proves anything is one more than a batch.
- A mediated single-row fact write: the write and one ledger insert, no other query; and a ledger append that fails rolls the write back — the atomicity claim, tested by behaviour rather than by counting `begin`/`commit`.
- A bulk write touching no fact field, 1,000 rows: one query, no `RETURNING` in it, one audit record, zero fact events.
- A `bulk_update` changing a fact field on 5,000 rows: one `UPDATE`, three ledger `INSERT`s (the 2,000-row batch), one audit record, 5,000 fact events carrying the same `operation_id`.
- A `bulk_update` setting a fact field to its current value on 1,000 rows: zero fact events, one audit record.
- A scoped `all` over 1,000 rows: one query, one decision record.
- One tripwire, generously bounded, on the committed repo: the 5,000-row `bulk_update` completes in under ten seconds. It catches an order-of-magnitude mistake and nothing subtler.

**Numbers, not gates.** Real performance characterization is `mix turnstile.bench`, a Benchee suite run on demand — seam overhead per operation, bulk write throughput, scope compilation — whose output is a committed table in the docs, refreshed when the seam changes, never a CI assertion. Revocation latency is a third thing: a measurement that ships in the evidence and is compared with the PS-4 value, taken end to end on the committed repo and reported, not bounded.

## §8 Bulk writes and fact fields

- A fact schema declares its fact columns; only changes to those columns are facts. A single-row write emits one fact event per changed fact field (changesets carry only actual changes). A bulk write whose `set` or `inc` touches no fact field emits none: one decision record, outcome count, no `RETURNING` requested.
- Plain `update_all`, `delete_all`, `insert_all` against fact fields are refused by the seam when the configured ledger asks for it — the Ecto ledger does; event-store mode and mode none do not — with a pointer to `turnstile_ledger`'s `Turnstile.Facts.bulk_update/3`, `bulk_delete/2`, `bulk_insert/3`.
- `bulk_update` adds, per field it sets, a null-safe "is different" condition in plain Ecto: `is_nil(field) or field != ^value`, or `not is_nil(field)` when the value is nil. No fragment; portable. Computed sets (`inc`, fragments) cannot be compared in advance and record every affected row, which is correct.
- The bulk API needs the affected rows back; the dialect answers how (§11): `RETURNING` ids (deleted rows for deletes) where the database supports it, else select the ids first under the dialect's lock clause, in the same transaction, then write.
- Fact events are inserted with `insert_all` in batches of `fact_insert_batch` inside the same transaction as the write; each carries the `operation_id`, indexed.
- The audit record for the operation carries count, `operation_id`, and min/max position; an investigator pulls rows by `operation_id`. The example's chained store writes one chained record per operation.
- Smell: a job that flips a million authorization facts nightly is a modeling error — something bookkeeping-shaped has been declared a fact.

## §9 Ledger positions

The Ecto ledger's position is a sequence. Sequences interleave across concurrent transactions and a lower position can commit after a higher one, so a reader that has seen position N has not necessarily seen everything below it. The reader behind projection, reconcile, and replay is a dialect concern (§11): `Dialect.Postgres` reads only positions below the oldest position still held by an in-flight transaction — snapshot `xmin` against each row's transaction id; `Dialect.Generic` reads behind a fixed lag. The alternative, a single counter row locked by every fact-writing transaction, gives commit-ordered positions at the cost of serializing those transactions; a dialect may choose it where the database serializes writers anyway or where the safe reader proves troublesome. Tier 1 interleaves two transactions on Postgres and asserts no event is skipped. A bulk write's positions are a range with holes, which is why its audit record names the `operation_id` and not only the range.

## §10 Ledger modes: what the statement can claim

| Mode | Who owns the facts | What the library does | What the statement can claim |
|---|---|---|---|
| Event store | the application's event store | reads it through the fact mapping; appends policy-version events through the same behaviour; needs no Ecto | replay exact; completeness is the application's claim about its store |
| Ecto ledger | the application's tables | one fact event per changed fact field in the same transaction, through the seam, into a library-owned table; genesis; reconcile | no fact without an entry inside the application after genesis; drift from outside detected within the reconcile interval; replay exact after reconcile |
| None | the application's tables | nothing | drift detection, point-in-time review, and account-management audit (AC-2(4)) printed "application must"; decision events carry no position; an adapter that requires a ledger (OpenFGA) printed unsupported, with a POA&M row |

Genesis: every current fact as an event at position zero, stamped "backfilled from tables on ⟨date⟩ by ⟨migration⟩"; reconcile runs from there; the statement prints the date. Append-only: the dialect's migration grants the application role insert and never update or delete on the ledger table; the statement prints the grant. A conformance case for the ledger behaviour ships with core so an implementation over another store can prove itself.

## §11 Dialects

`Turnstile.Ledger.Dialect` answers five questions. `Postgres` is the reference and the only dialect the suite runs; `Generic` takes the portable answer; nothing else ships until asked.

| Question | `Postgres` | `Generic` | Notes |
|---|---|---|---|
| Rows back from a bulk write | `RETURNING` ids, deleted rows for deletes | select ids first under the lock clause, then write | SQLite and SQL Server can return rows; MySQL cannot |
| `fact_insert_batch` | 2,000, against 65,535 bound parameters per statement | a few hundred | SQLite ~32,000 parameters; SQL Server 2,100 |
| Reader strategy | snapshot `xmin` visibility | fixed lag behind the head | SQLite serializes writers and needs neither; the counter row is a third option |
| Lock clause for select-then-write | `FOR UPDATE` | per database | SQL Server spells it differently; SQLite has none |
| Append-only grant | `GRANT INSERT`, no `UPDATE`/`DELETE`, to the application role | same, per database | the statement prints the grant |

The statement prints the database, the dialect, the path each mechanism took, and `tested` or `untested` from the suite's own record.

## §12 Pinned sources, bump procedure, assessment glossary

`apps/turnstile_assess/priv/sources.exs` pins three releases and the files sit beside it: the SP 800-53 catalog (OSCAL; 5.2.0 at the time of writing), the FedRAMP Rev 5 Moderate baseline profile (OSCAL, from the fedramp-automation repository), the FedRAMP 20x machine-readable docs. The lint checks every scenario's control id against the catalog, its baseline membership against the profile, and its KSI id against the docs.

Bump procedure (`docs/how-to/bump-sources.md`): update the pin and file; run the lint; its diff lists scenarios whose citations changed, were withdrawn, or gained a KSI; re-cite; regenerate; commit the diff with the bump.

SSP vocabulary the generator prints. Implementation status: Implemented, Partially Implemented, Planned, Alternative Implementation, Not Applicable. Origination: Service Provider Corporate; Service Provider System Specific; Service Provider Hybrid; Configured by Customer; Provided by Customer; Shared; Inherited from pre-existing authorization. Example defaults: programs, lists, and designators an agency sets → Configured by Customer; CUI training → Service Provider Corporate; what the library or application implements → Service Provider System Specific. POA&M columns: weakness, detection source, remediation plan, scheduled completion, milestones, status. Assessment glossary: control, enhancement, parameter, implementation status, origination, baseline, profile, SSP, SAR, POA&M, CRM, 3PAO, authorization boundary, inventory, continuous monitoring, Key Security Indicator, Ongoing Authorization Report.

## §13 The OpenFGA adapter

Design note, model, tuple mapping, and the projector's rules: `OPENFGA.md`. Declaration summary — capabilities: explain native; C3, C4, C9 native; C8 adapter-side; `scope` limited; write gates unsupported; requires a ledger. Parameters: consistency per operation, drain interval, check-cache TTL, `ListObjects` cap. Inventory: the server and its datastore. Projection cases in Tier 1: measured lag; drift from a tuple deleted through the API directly, caught by reconcile; a re-drain after a simulated crash converges.

## §14 Test environment

See `TESTING.md`: a Nix flake pins the toolchain and provides Postgres, Cerbos, and OpenFGA binaries; `mix test` starts an ephemeral cluster per run (owner and app roles, a sandboxed and a committed database); every test owns its state so `async: true` is the default; `:committed` and `:tripwire` are the tagged exceptions; shape tests run on every pull request and benchmarks on demand.

Two tracks, for orientation: **Rev 5** — an SSP with a control implementation statement per control, assessed by a 3PAO, monthly continuous-monitoring deliverables, OSCAL accepted. **20x** — Key Security Indicators, sixty-one for Moderate at the pinned release, each mapped to 800-53 controls, validated by automation the 3PAO reviews, reported quarterly in an Ongoing Authorization Report; the Moderate pilot ran over the winter of 2025–26. Impact-level names are being replaced; the level is a profile input and appears in no module name.
