# The example: controlled unclassified information

The application every adapter is measured against: a document store under the marking rules of 32 CFR Part 2002, the controls of the CUI Registry, and thirteen rules, C1 to C13, that `docs/reference.md` §3 states. The domain, its contexts, its web layer, and every Tier 2 scenario live here; a thin application (`example_rbac`, `example_postgres`, `example_cerbos`, `example_fga`) binds one adapter to it and adds only what that adapter needs. This package has no application callback and starts nothing.

- The schemas. `Example.Document`, `Example.Portion`, `Example.Marking`, `Example.Proposal`, `Example.Program`, `Example.Assignment`, `Example.OfficeRole`, `Example.Agency`, `Example.Office`, and `Example.Category` declare an object type with `use Turnstile.Schema`, and the facts and relationships a rule reads. A Document carries its Marking, its Portions, and its Proposals, so a decision on the document admits queries and nested writes of the rows it carries. `Example.User`, `Example.AccountRole`, and `Example.OverrideReport` are the account, the override permission, and the override's report.
- `Example.Documents`: the reads and the marking writes. `read/3` asks the port for `read` and returns the document with its banner (C1, C2); `read_redacted/3` asks for `read_redacted` on the document and `scope` over its portions, and returns the portions the subject may read (C4); `list/2` is `scope` over documents. `change_marking/4`, `set_decontrol/4`, and `decontrol/3` are C7 operations, refused by the port without a designator role and a fresh session (C8), and a banner that would drop a portion's control is refused in the domain (C4). `change_portion_marking/4` widens the banner in the same transaction. `override_read/4` is C10: a privileged subject with the permission and a justification reads outside C1, emits `[:example, :override, :read]`, and is reported to the designating office.
- `Example.Proposals`: separation of duties (C9). `propose/4` needs `propose_marking` on the document; `approve/3` needs `approve_marking` on the proposal, which the adapters give to an approver other than the proposer, and applies the marking as a nested write under the proposal's decision.
- `Example.Accounts` and `Example.Sessions`: the roles an account holds, written under a declared exemption because role administration is not a rule of the example, and the re-authentication window (C8) the adapters that compute in code compare against `reauthenticated_at`.
- `Example.Controls`: the four control kinds and the union of markings that is a document's banner.
- `Example.Audit`: the hash-chained audit store (AU-9), fed by every `stop` event of the port and by the override event; `verify/1` names the first record whose hash no longer holds.
- `Example.Review`: the access review report, who may do what on the documents of each agency and every privileged account, from the port's `review` under one record for the reviewer.
- `Example.Repo` and `Example.OwnerRepo`: the application-role repo every query on a protected schema passes through with a decision or an exemption, and the owner-role repo for migrations and truncation.
- `Example.Router`, `Example.DocumentController`, `Example.ProposalController`, and `Example.Plug.Identity`: the JSON routes and the plug that reads the caller's account, session, and re-authentication time from the headers an authenticating proxy sets. The plug authorizes nothing; every rule is asked at the port by the contexts.
- `Example.Migrations.Domain`: the domain tables as a helper the thin application's first migration calls; no foreign key cascades into a fact schema, so a revocation deletes nothing but the fact.
- `test/support`: `Example.Fixture`, the world every scenario starts from; `Example.Scenarios`, every scenario of `docs/reference.md` §3a, declared once and defined in a thin application's test module with `use Example.Scenarios, capabilities: ThinApp.Capabilities, rules: ThinApp.Rules`, with the count test of `docs/testing.md` §6; `Example.Scenarios.Rules`, the two policy operations a thin application supplies. The bodies for the ledger scenarios fail plainly until the ledger stage adds them.

`glossary.md` defines the words this package owns. The package's own tests cover the contexts and the web layer under `Turnstile.Adapter.Fake`; the scenarios run in each thin application, under the adapter it binds, and never here.

## The identity headers

| Header | Fact |
|---|---|
| `x-user-id` | The account; its row gives the subject's kind |
| `x-session-id` | The session id the audit record names |
| `x-reauthenticated-at` | The re-authentication time (C8), passed to the port as the fact `reauthenticated_at` |
