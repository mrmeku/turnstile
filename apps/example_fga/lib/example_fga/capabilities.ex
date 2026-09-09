defmodule ExampleFga.Capabilities do
  @moduledoc """
  What this binding declares about each rule. One rule is limited, and the
  rest are native with the component that enforces them named.

  Three of the rules the graph carries better than anything else does: the
  implied controls of a specified category (C3) and a portion's controls (C4)
  are inherited by walking rather than copied, and separation of duties (C9)
  is the approver of the office less the proposer. What the graph does not
  carry is the size of a listing: `ListObjects` answers up to a cap, so a
  scope above it is a filter per page rather than a rule over identifiers,
  which is what the limited level records.

  Re-authentication (C8) is a fact about the session rather than about a
  relationship, so the adapter reads it from the environment through the
  guard this application binds, before the server is asked at all.
  """

  @behaviour Turnstile.Capabilities

  @impl Turnstile.Capabilities
  def capability(:c7), do: {:native, by: :seam, note: "the write is refused by the seam before the model is asked"}

  def capability(:c8),
    do: {:native, by: :adapter, note: "the guard reads reauthenticated_at from the environment before the call"}

  def capability(:c10), do: {:native, by: :application, note: "permission, justification, event, and report in code"}

  def capability(:c11),
    do: {:native, by: :engine, note: "every check walks the current tuples, up to the projector's lag"}

  def capability(:c12), do: {:native, by: :adapter, note: "the latency is measured, the drain included, never asserted"}

  def capability(:c13),
    do: {:limited, by: :engine, note: "ListObjects answers under the cap, and a filter per page above it"}

  def capability(_rule), do: {:native, by: :engine, note: ""}
end
