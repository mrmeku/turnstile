defmodule ExampleRbac do
  @moduledoc """
  The example bound to RBAC in code: the policy module that states the
  example's rules as a role table, grants, and predicates; the boot that
  binds it to `Example.Repo`; the capability declaration; and the
  migrations that create the example's tables and the ledger's counter.
  Nothing of the domain lives here.
  """

  use Boundary,
    deps: [Example, Turnstile, Turnstile.Code, Ecto],
    exports: [Application, Capabilities, Policy, Predicates]
end
