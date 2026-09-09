defmodule ExamplePostgres.Capabilities do
  @moduledoc """
  What this binding declares about each rule: every rule is native. The
  banner (C4) is the union the domain keeps at write time, beside the
  policy that answers a portion under its own marking; the marking gates
  (C7) are `WITH CHECK` policies the database applies to the write itself,
  so a write that never passed the seam is refused too; the override (C10)
  is application code reading under a declared exemption, which the
  exemption policy of the application role admits; the rest is the policies
  on the tables, evaluated by the database at every statement.
  """

  @behaviour Turnstile.Capabilities

  @impl Turnstile.Capabilities
  def capability(:c4), do: {:native, by: :application, note: "the union of the portions is enforced at write time"}
  def capability(:c7), do: {:native, by: :database, note: "the write gate refuses the write with no application code"}
  def capability(:c8), do: {:native, by: :database, note: "the gate reads turnstile.reauthenticated_at as a setting"}
  def capability(:c10), do: {:native, by: :application, note: "permission, justification, event, and report in code"}
  def capability(:c12), do: {:native, by: :adapter, note: "the latency is measured and recorded, never asserted"}
  def capability(_rule), do: {:native, by: :database, note: ""}
end
