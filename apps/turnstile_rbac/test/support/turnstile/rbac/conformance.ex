defmodule Turnstile.Rbac.Conformance do
  @moduledoc """
  The conformance artifact of RBAC in code: the role table and the
  predicates that encode the neutral fixture's rule, the modules the
  conformance suite binds. The test run compiles them; an application never
  loads them.
  """

  use Boundary,
    top_level?: true,
    deps: [Turnstile, Turnstile.Conformance, Turnstile.Rbac, Turnstile.Fixture, Ecto],
    exports: [Assignment, Predicates, Roles, Tightened, Versions]
end
