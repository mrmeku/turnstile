defmodule Turnstile.Conformance do
  @moduledoc """
  The conformance mechanisms: the scenario table of the reference's §3a, the
  `scenario` macro and the count that Tier 2 rests on, and the adapter case
  template that Tier 1 is. Shipped in core so every adapter, in this
  repository or outside it, proves itself against the same contract.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Turnstile,
      Turnstile.Test,
      Turnstile.Test.Sandbox,
      Turnstile.Fixture,
      Ecto,
      ExUnit,
      ExUnitProperties,
      StreamData,
      Mox
    ],
    exports: [AdapterCase, AdapterCase.Laws, Case, Gen, LedgerCase, Projected, RepoCase, Scenario, Scenarios, Seed]
end
