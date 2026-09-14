defmodule ExampleRbac do
  @moduledoc """
  The example bound to RBAC in code: the policy module that states the
  example's rules as a role table, grants, and predicates; the boot that
  binds it to `Example.Repo`; and the migrations that create the example's
  tables. Nothing of the domain lives here.
  """

  # The predicates are exported although they are under `core/`, because the
  # tightened policy the scenarios publish is a policy of this application
  # and names what the boot policy names; it sits in test support, and so in
  # a boundary of its own, which is the only reason this has to be said.
  use Boundary,
    deps: [Example, Turnstile, Turnstile.Code, Ecto],
    exports: [Application, Core.Predicates, Policy]
end
