defmodule ExampleCerbos.Capabilities do
  @moduledoc """
  What this binding declares about each rule. Three rules are limited, and
  each note says where the part the policy language does not carry lives.

  The derivations (C3) and the portion's inherited decontrol (C4) are in the
  subqueries the attribute declarations name, so the policy tests membership
  in a set the database derived rather than deriving it itself. The query
  plan (C13) holds where the sidecar's plan compiles to a rule over declared
  attributes, and an expression the compiler does not carry is refused
  rather than narrowed.
  """

  @behaviour Turnstile.Capabilities

  @impl Turnstile.Capabilities
  def capability(:c3),
    do: {:limited, by: :engine, note: "the implied controls are derived in the subquery the declaration names"}

  def capability(:c4),
    do: {:limited, by: :engine, note: "a portion's decontrol is its document's, so the test is in the subquery"}

  def capability(:c7), do: {:native, by: :seam, note: "the write is refused by the seam before the policy is asked"}
  def capability(:c10), do: {:native, by: :application, note: "permission, justification, event, and report in code"}
  def capability(:c12), do: {:native, by: :adapter, note: "the latency is measured and recorded, never asserted"}

  def capability(:c13),
    do: {:limited, by: :engine, note: "scope holds where the plan compiles, and any other expression fails closed"}

  def capability(_rule), do: {:native, by: :engine, note: ""}
end
