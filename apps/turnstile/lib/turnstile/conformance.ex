defmodule Turnstile.Conformance do
  @moduledoc """
  The conformance mechanisms: the scenario table of the reference's §3a, the
  `scenario` macro and the count that Tier 2 rests on, and the adapter case
  template that Tier 1 is. Shipped in core so every adapter, in this
  repository or outside it, proves itself against the same contract. The
  population a Tier 1 run is written over comes from the caller, as a
  `Turnstile.Conformance.World`, so nothing here names a schema or a rule.
  """

  use Boundary,
    top_level?: true,
    deps: [Turnstile, Turnstile.Test, Ecto, ExUnit, ExUnitProperties, StreamData],
    exports: [
      AdapterCase,
      AdapterCase.Laws,
      Case,
      Gen,
      Law,
      RepoCase,
      RepoCase.Rows,
      Scenario,
      Scenarios,
      Seed,
      Versions,
      World
    ]
end
