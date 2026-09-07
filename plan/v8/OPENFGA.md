# Turnstile — the OpenFGA adapter: design note
*Mode: Explanation. The design note for the fourth adapter, `turnstile_fga`. It began as an exercise — does the plan's altitude hold if an adapter is a relationship graph? — and became the decision: the port, the seam, and the events survive untouched, three of the CUI rules come out cleaner on a graph than anywhere else, and the costs are the kind of thing the statement exists to print. §7 lists the three core amendments the exercise found; plan v8 applies them for every adapter.*

## 1. Zanzibar in the plan's words

A Zanzibar-style system stores **tuples** — `(user, relation, object)`, such as `user:alice member program:9` — and an **authorization model** that says how relations compose: directly assigned, computed from other relations on the same object, or followed through a related object ("members of the document's program"). OpenFGA is the open-source implementation: a server with its own datastore, an API of `Check`, `BatchCheck`, `ListObjects`, `ListUsers`, `Expand`, `Read`, `Write`, and `ReadChanges`, models that are immutable and versioned by id, and since 2023 **conditions** — small CEL expressions on tuples, evaluated against a context sent with each check.

| Plan concept | OpenFGA |
|---|---|
| subject, object, operation | user, object, relation (an operation is a relation such as `can_read`) |
| environment | the `context` sent with a check, consumed by conditions |
| subject attribute | a tuple to a reified entity: `user:alice member country:US` |
| object attribute | a tuple on the object, or a condition parameter on one |
| relationship granted / revoked | a tuple written / deleted |
| policy version published | an authorization model written; its id |
| `authorize`, `check`, `batch` | `Check`, `BatchCheck` |
| `scope` | `ListObjects` → `dynamic([d], d.id in ^ids)` |
| `review` | `ListObjects` per subject, or `ListUsers` per object |
| `explain` | `Expand` — the relation tree, which is the path explanation the plan noted as FGA's strength |
| the adapter's working state | the FGA store — a **projection** of the ledger, fed by a projector |
| revocation latency | commit + projector drain + FGA write + check-cache TTL |

The one structural difference from the three shipped adapters: their working state *is* the application's tables. FGA's is a copy, in another store, kept current by a **projector**. That is what the plan's `Turnstile.Projection` behaviour was reserved for, and it is the shape of a transactional outbox: the ledger is the outbox, its read-from-position contract is the drain, and the tuple mapping is the declarative mirror.

## 2. The CUI domain as an FGA model

Everything in the example is expressible, and two rules come out cleaner than under Cerbos. The idiom that does the work: a control on a marking is a **wildcard flag** — a tuple `user:* fedonly_applies document:1` meaning "this applies to everyone" — and the block is the flag minus the users who clear it. Implication (C3) and portions (C4) are tuple-to-userset, so nothing is copied. Decontrol (C5) is a condition on the flag and category tuples. Separation of duties (C9) is `but not proposer`.

```
model
  schema 1.1

type user

type country
  relations
    define member: [user]

type employment
  relations
    define member: [user]

type agency
  relations
    define domestic: [country]
    define federal: [employment]
    define operator: [user]
    define domestic_member: member from domestic
    define federal_member: member from federal

type office
  relations
    define agency: [agency]
    define designator: [user]
    define approver: [user]
    define member: designator or approver
    define domestic_member: domestic_member from agency
    define federal_member: federal_member from agency
    define operator: operator from agency

type program
  relations
    define agency: [agency]
    define lead: [user]
    define member: [user] or lead

type category
  relations
    define fedonly_applies: [user:*]
    define noforn_applies: [user:*]

type document
  relations
    define program: [program]
    define designating_office: [office]
    define category: [category, category with before_decontrol]
    define listed: [user]
    define releasable_to: [country]

    define fedonly_applies: [user:*, user:* with before_decontrol] or fedonly_applies from category
    define noforn_applies: [user:*, user:* with before_decontrol] or noforn_applies from category
    define relto_applies: [user:*, user:* with before_decontrol]
    define list_applies: [user:*, user:* with before_decontrol]

    define lawful_purpose: member from program or member from designating_office
    define fedonly_clear: federal_member from designating_office
    define noforn_clear: domestic_member from designating_office
    define relto_clear: member from releasable_to

    define blocked_by_fedonly: fedonly_applies but not fedonly_clear
    define blocked_by_noforn: noforn_applies but not noforn_clear
    define blocked_by_relto: relto_applies but not relto_clear
    define blocked_by_list: list_applies but not listed
    define blocked: blocked_by_fedonly or blocked_by_noforn or blocked_by_relto or blocked_by_list

    define can_read: lawful_purpose but not blocked
    define can_change_marking: designator from designating_office
    define can_override: operator from designating_office

type proposal
  relations
    define office: [office]
    define proposer: [user]
    define can_approve: approver from office but not proposer

condition before_decontrol(decontrol_at: timestamp, current_time: timestamp) {
  current_time < decontrol_at
}
```

Rule by rule. C1 is `lawful_purpose`. C2 is `can_read: lawful_purpose but not blocked` — every flag present must be cleared, and an absent flag blocks nobody. C3: a Specified category carries its own wildcard flags, and `fedonly_applies from category` inherits them; nothing is copied. C4 would be `fedonly_applies from portion` — the same idiom, still ⟨open 1⟩. C5: a document with a decontrol writes its flag and category tuples *with* `before_decontrol` and the date; one without writes them plain; after the date the flags evaluate false and only C1 remains. C6: `listed` is a per-document grant and combines with nothing — the model has no path from `listed` to `lawful_purpose`. C7 is `can_change_marking`; the write itself is gated by the seam, not by FGA. C8, re-authentication, is not modeled: it is a fact about the session, and putting it in a condition would make every use of `designator` demand session context, so the adapter checks it from the environment before calling FGA, as the code adapter does. C9 is `can_approve: approver from office but not proposer`, which is nicer than either code or Cerbos. C10 is `can_override` plus the justification and the event, in code. C11 holds per check, up to the projector's lag. C12 is measured. C13 is `ListObjects`, by FGA's definition of it.

## 3. The tuple mapping

The example's fact mapping already turns schema changes into the four fact kinds. The FGA adapter adds a second mapping, from fact events to tuple writes and deletes. Attributes become reified entities — a country, an employment kind — because a graph compares by walking, not by equality.

| Fact | Tuples (user · relation · object) |
|---|---|
| Assignment(U, P, member or lead) | `user:U · member \| lead · program:P` |
| OfficeRole(U, O, designator or approver) | `user:U · designator \| approver · office:O` |
| Program in Agency; Office in Agency | `agency:A · agency · program:P`; `agency:A · agency · office:O` |
| Document's program and designating office | `program:P · program · document:D`; `office:O · designating_office · document:D` |
| Document's categories | `category:C · category · document:D`, with `before_decontrol{decontrol_at}` when set |
| Marking's controls | `user:* · fedonly_applies · document:D` (and the others), with the condition when set |
| Marking's list | `user:U · listed · document:D`, plus the `user:* · list_applies · document:D` flag |
| REL TO countries | `country:CC · releasable_to · document:D` |
| Specified category's implied controls | `user:* · fedonly_applies · category:C`, written once per category |
| User's employment; nationality | `user:U · member · employment:federal`; `user:U · member · country:CC` |
| Agency's domestic country; federal marker | `country:CC · domestic · agency:A`; `employment:federal · federal · agency:A` |
| Privileged user | `user:U · operator · agency:A` |
| Proposal (C9) | `office:O · office · proposal:P`; `user:U · proposer · proposal:P` |
| Decontrol set or changed | delete and rewrite the flag and category tuples with the new parameter |
| Policy version | write the model; record the model id and the DSL text (small) in the policy-version event |

## 4. The projector

`Turnstile.Fga.Projector` implements `Turnstile.Projection`: it reads fact events from the ledger's visibility-safe reader, from its checkpoint, applies the tuple mapping, writes in batches (OpenFGA's default `maxTuplesPerWrite` is 100 ⟨verify⟩), and advances the checkpoint in the application's database. Three things the agent must know:

- **Writes are not idempotent.** OpenFGA rejects a write of a tuple that already exists and a delete of one that does not, so the drain reads before it writes, or tolerates exactly those two errors; either way a re-drain after a crash must converge.
- **Genesis is a rebuild.** `rebuild/1` folds from position zero and writes every tuple; at a hundred tuples per call, a million facts is ten thousand calls — minutes, offline, once.
- **Reconcile compares the fold to `Read`.** FGA's `Read` pages tuples by object type; drift is a tuple present in one and not the other. Cost is proportional to tuples, so the interval is longer than the Ecto ledger's table comparison, and the statement prints it.

The adapter therefore **requires a ledger** — event-store or Ecto — and declares so; in ledger mode none there is nothing to drain, and the statement would print the adapter unsupported with a POA&M row rather than pretend dual writes are a projection.

## 5. Decisions, scope, replay

**Decisions.** `Check` with the model id pinned per request and `consistency` set per operation — `HIGHER_CONSISTENCY` for anything under C7–C10, `MINIMIZE_LATENCY` allowed for reads, a declared parameter the statement prints. The decision event carries the model id as its policy version. It also needs something the current event does not distinguish: the ledger *head* at decision time and the position the projector had *applied*. For the three shipped adapters those are the same number; for a projection they differ by the lag, and replay must use the applied position, because that is the state the engine actually saw.

**Scope.** `ListObjects` returns ids, so `scope` is `dynamic([d], d.id in ^ids)` — the `batch_ids_cap` elision applies to the recorded rule. `ListObjects` has a configurable result cap and deadline, on the order of a thousand ⟨verify⟩, so the capability is *limited*: above the cap the seam falls back to `filter` per page with `BatchCheck`, and the statement says so. Tenant-scoping the query first (`d.agency_id == ^agency`) keeps most lists under the cap.

**Replay.** Fold the ledger to *t*, write the tuples into a throwaway OpenFGA with the in-memory datastore, pin the model in force at *t* — models are immutable and kept, so it is still there — and `Check`. Heavier than Cerbos's replay because the state must be loaded, lighter than Postgres's because no schema is involved.

**Revocation latency** decomposes as commit, drain interval, FGA write, check-cache TTL if the cache is enabled, and the consistency mode; Tier 1 measures it end to end as before.

## 6. What the example would change

- **A new package, `turnstile_fga`**: the adapter (`Check`, `BatchCheck`, `ListObjects`, `Expand` behind the port), the projector and its checkpoint schema and migration, the declaration (capabilities: explain native, C3/C4 native, C9 native, `scope` limited, write gates unsupported, C8 adapter-side; `requires_ledger: true`; parameters: consistency per operation, drain interval, cache TTL; two inventory items).
- **In the example**: `priv/fga/model.fga` as above, published by CI with the model id recorded as a policy version; `Example.Authz.FgaMapping`, the tuple mapping beside the fact mapping; configuration for endpoint, store, model pin, consistency, drain interval; a checkpoint migration. Controllers, contexts, and the seam do not change — the port is the port.
- **Testing**: `openfga` from nixpkgs ⟨verify⟩ in the flake; one `openfga run --datastore-engine memory` per test run; a **store per test** (`CreateStore`), which is FGA's own isolation unit, so Tier 2 stays async; Tier 1 gains projection cases — measured lag, drift from an out-of-band tuple delete, convergence of a re-drain.
- **Statement**: two inventory items (the server and its datastore — sharing the application's Postgres instance as a separate database keeps it to one engine); origination like the code adapter; POA&M rows for `scope` above the cap and for write gates; the consistency parameter and drain interval printed.
- **Adoption**: a tag `v10c-openfga` beside Postgres and Cerbos.

## 7. What the exercise found

The port, the seam, the fact events, the generator, and the example's controllers survive untouched — the altitude test passes. Three small things in core change, applied in plan v8 for every adapter, because they make the projection concept the plan already names honest:

1. **The decision event distinguishes `applied_position` from `head_position`.** Equal for adapters whose state is the tables; the lag for a projection; replay uses `applied`.
2. **Declarations gain `requires_ledger`.** The generator prints an adapter that requires a ledger as unsupported under mode none, with a POA&M row.
3. **The projection behaviour gains `rebuild/1` and a checkpoint**, and Tier 1 gains the three projection cases, activated only for adapters that declare a projection.

What the exercise did not change: the costs. Two inventory items, a second store holding copies of authorization facts inside the boundary, a drain interval inside the revocation clock, a capped `ListObjects`, no write gates, and a reconcile that walks every tuple. Against those: C3, C4, and C9 are the cleanest of any adapter, explanations are paths, and a domain with real hierarchy — folders in folders, teams in teams — wants this engine. The adapter is in, with those costs printed in its statement beside the other three, which is how a team is meant to choose.
