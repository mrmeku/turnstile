defmodule ExampleCerbos do
  @moduledoc """
  The example bound to a policy sidecar: the attribute declarations that say
  what the policies may read, the subqueries behind them, the policy files
  the sidecar serves, the boot that binds them to `Example.Repo`, the
  capability declaration, and the migrations that create the example's
  tables and the ledger's counter. Nothing of the domain lives here.

  The version identifier is the commit of the repository the policy files
  come from, since a directory a sidecar reads carries no history of its
  own. It arrives as configuration, which is how a deployment tells the
  application which commit it is serving.
  """

  use Boundary,
    deps: [Example, Turnstile, Turnstile.Cerbos, Ecto],
    exports: [Application, Attributes, Capabilities, Facts]

  @author "example_cerbos"
  @approval "docs/reference.md §3, as policy files under review"

  @doc "Who wrote the rules, as the record of a policy version carries it."
  @spec author() :: String.t()
  def author, do: @author

  @doc "What approved them, as the record of a policy version carries it."
  @spec approval() :: String.t()
  def approval, do: @approval
end
