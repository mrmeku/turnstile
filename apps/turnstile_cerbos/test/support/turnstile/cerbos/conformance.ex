defmodule Turnstile.Cerbos.Conformance do
  @moduledoc """
  The conformance artifact of the Cerbos adapter: the attribute
  declarations and the subqueries behind them, which encode where the
  neutral fixture's values come from. The policies that read those
  attributes are the YAML under `priv/conformance/`, which is what the
  sidecar reads. The test run compiles the module; an application never
  loads it.
  """

  use Boundary,
    top_level?: true,
    deps: [Turnstile, Turnstile.Cerbos, Turnstile.Fixture, Ecto],
    exports: [Attributes, Memberships]
end
