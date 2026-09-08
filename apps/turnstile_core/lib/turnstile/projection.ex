defmodule Turnstile.Projection do
  @moduledoc """
  How an adapter's state relates to the ledger, for an adapter that keeps
  state of its own. The projector drains fact events from a checkpoint and
  applies them; `rebuild/1` folds from position zero into a fresh store and
  returns its reference; `reconcile/1` compares the fold with the state and
  reports drift. Each callback takes the projector's own configuration
  struct and is driven, never scheduled, by the tests.
  """

  alias Turnstile.Error
  alias Turnstile.Projection.Drain
  alias Turnstile.Projection.Drift

  @type failure :: {:error, Error.Engine.t()}

  @doc "The position the state has applied."
  @callback checkpoint(struct()) :: {:ok, non_neg_integer()} | failure()

  @doc "Drain once from the checkpoint, apply, advance, and report the range."
  @callback drain_once(struct()) :: {:ok, Drain.t()} | failure()

  @doc "Fold from position zero into a new store and return its reference."
  @callback rebuild(struct()) :: {:ok, String.t()} | failure()

  @doc "Compare the fold with the state and report what differs."
  @callback reconcile(struct()) :: {:ok, Drift.t()} | failure()
end
