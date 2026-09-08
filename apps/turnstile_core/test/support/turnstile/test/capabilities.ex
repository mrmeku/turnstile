defmodule Turnstile.Test.Capabilities do
  @moduledoc """
  A capability declaration for core's own tests: every rule and guarantee is
  `native` by the adapter, except `:c3`, which is `unsupported`, so the
  conformance macros can be exercised on both branches.
  """

  @behaviour Turnstile.Capabilities

  @impl Turnstile.Capabilities
  def capability(:c3), do: {:unsupported, by: :adapter, note: "the test declaration marks C3 unsupported"}
  def capability(_rule), do: {:native, by: :adapter, note: "the test declaration"}
end
