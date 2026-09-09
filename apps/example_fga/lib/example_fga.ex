defmodule ExampleFga do
  @moduledoc """
  The example bound to a relationship graph: the model the store is published
  from, the mapping that turns the example's fact events into tuples, the
  guard that holds the re-authentication window outside the graph, the boot
  that binds them to `Example.Repo`, the capability declaration, and the
  migrations that create the example's tables, the ledger, and the
  projector's checkpoint. Nothing of the domain lives in the adapter.

  The version identifier is the id the server gives a model when it is
  published, so a rule change needs no configuration: the text of
  `priv/fga/model.fga` is the artifact under review, and its digest is what
  decides whether a boot publishes anything.

  This binding requires a ledger. The store is a projection of the ledger
  rather than the application's tables, so there is no mode in which the
  facts reach the engine without one.
  """

  use Boundary,
    deps: [Example, Turnstile, Turnstile.Fga, Ecto],
    exports: [Application, Capabilities, Guard, TupleMapping]

  @author "example_fga"
  @approval "docs/reference.md §13, as the model under review"
  @model "priv/fga/model.fga"

  @doc "Who wrote the rules, as the record of a policy version carries it."
  @spec author() :: String.t()
  def author, do: @author

  @doc "What approved them, as the record of a policy version carries it."
  @spec approval() :: String.t()
  def approval, do: @approval

  @doc """
  The model file the binding names, given relative to this application's priv
  directory unless it is absolute, so a release finds the text where it was
  installed.
  """
  @spec model() :: Path.t()
  def model do
    case Path.type(@model) do
      :absolute -> @model
      _relative -> Application.app_dir(:example_fga, @model)
    end
  end
end
