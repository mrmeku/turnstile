defmodule Turnstile.Fga do
  @moduledoc """
  The OpenFGA adapter. Facts become tuples in a store of the engine's own,
  rules become a model that is immutable and named by id, and the projector
  drains the ledger into that store, which is why this adapter requires a
  ledger: its working state is a copy rather than the application's tables.

  What this package holds, and what each piece is for:

  - `Turnstile.Fga.Client`, the only path to the server. Eight calls, each
    answering a value or an engine error, none of them raising.
    `Turnstile.Fga.Client.Fake` is the same behaviour on an `Agent`, which
    is where the projector's own cases run.
  - `Turnstile.Fga.TupleMapping`, what an application states about its
    facts: which objects an event can have changed, and which tuples an
    object requires. Both are read from the fold rather than from one event,
    which is what lets the projector write differences.
  - `Turnstile.Fga.Projector`, `Turnstile.Projection` over that mapping:
    a drain by difference, a checkpoint in the application's own database, a
    rebuild into a store of its own, and a reconcile against what the store
    reports.
  - `Turnstile.Fga.Migration`, the checkpoint table, which a thin
    application's migration creates.

  The port callbacks are not in this module yet. What is here is the
  mechanism every decision rests on: the client, the mapping, the
  projector, and the checkpoint.
  """

  use Boundary,
    deps: [Turnstile, Turnstile.Ledger.Reader, Ecto, NimbleOptions],
    exports: [
      Checkpoint,
      Client,
      Client.BatchCheck,
      Client.Check,
      Client.Expand,
      Client.ListObjects,
      Client.Page,
      Client.Read,
      Client.Tree,
      Client.Write,
      Condition,
      Consistency,
      Projector,
      TupleKey,
      TupleMapping
    ]
end
