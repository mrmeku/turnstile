defmodule Turnstile.Conformance do
  @moduledoc """
  The conformance mechanisms: the law table of `docs/conformance.md` §2, the
  adapter case that runs it, and the repo case that holds a mediated repo to
  the seam's guarantees. Shipped in the package so every adapter, in this
  repository or outside it, proves itself against the same contract. The
  population a run is written over comes from the caller, as a
  `Turnstile.Conformance.World`, so nothing here names a schema or a rule.
  """

  use Boundary,
    top_level?: true,
    deps: [Turnstile, Turnstile.Test, Ecto, ExUnit, ExUnitProperties, StreamData],
    exports: [
      AdapterCase,
      AdapterCase.Laws,
      Gen,
      Law,
      RepoCase,
      RepoCase.Rows,
      Seed,
      Versions,
      World
    ]
end
