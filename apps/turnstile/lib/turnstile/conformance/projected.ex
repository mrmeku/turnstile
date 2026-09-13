defmodule Turnstile.Conformance.Projected do
  @moduledoc """
  What the three projection cases of Tier 1 need from an adapter that
  declares a projection, beyond `Turnstile.Projection` itself: a way to
  write into its state behind the projector's back, and a configuration
  under which the next drain fails after applying part of what it read. The
  cases are defined only when `use Turnstile.Conformance.AdapterCase` names
  a module implementing both behaviours in its `projection:` option, and
  they read the projection's configuration struct from the test context
  under `:projection`, which the adapter's own `setup` supplies.
  """

  @doc "Write one fact into the state directly, so `reconcile/1` has drift to report."
  @callback disturb(struct()) :: :ok

  @doc "A configuration whose next `drain_once/1` fails after applying part of its batch and before advancing."
  @callback interrupt(struct()) :: struct()
end
