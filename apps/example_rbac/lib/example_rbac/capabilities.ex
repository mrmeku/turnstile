defmodule ExampleRbac.Capabilities do
  @moduledoc """
  What this binding declares about each rule: every rule is native. The
  banner (C4) and the override (C10) are enforced by the example's own code
  under every adapter; the marking gates (C7) are enforced by the seam,
  which refuses the write without a decision; the rest is the policy
  module, evaluated by the adapter at every call.
  """

  @behaviour Turnstile.Capabilities

  @impl Turnstile.Capabilities
  def capability(:c4), do: {:native, by: :application, note: "the union of the portions is enforced at write time"}
  def capability(:c7), do: {:native, by: :seam, note: "the write is refused without a decision for the operation"}
  def capability(:c8), do: {:native, by: :adapter, note: "the predicate reads reauthenticated_at from the environment"}
  def capability(:c10), do: {:native, by: :application, note: "permission, justification, event, and report in code"}
  def capability(:c12), do: {:native, by: :adapter, note: "the latency is measured and recorded, never asserted"}
  def capability(_rule), do: {:native, by: :adapter, note: ""}
end
