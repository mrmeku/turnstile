defmodule ExampleFga.OutboxSetup do
  @moduledoc """
  What `Turnstile.Fga.OutboxCase` is run under here: a sandbox connection on
  the example's repo, then the store of the test's own that
  `ExampleFga.Store` creates and pins a model in. The drain writes into that
  store, so a test reads what its own passes wrote rather than what another
  test's did.

  The handler is a global one, and `ExampleFga.Application` attaches it for
  the whole run. The template attaches and detaches it around each of its
  own tests, so this puts the application's handler back when the test ends:
  a callback registered here runs after the template's, and a run left with
  no handler would leave every later test's writes unmarked.
  """

  use Boundary, top_level?: true, deps: [ExampleFga.Store, Turnstile.Fga, Turnstile.Dev.Sandbox]

  alias ExampleFga.Store
  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Outbox

  @doc "Check the repo out and give the calling process a store of its own."
  @spec setup(module(), map()) :: :ok
  def setup(repo, tags) do
    :ok = Sandbox.setup(repo, tags)
    ExUnit.Callbacks.on_exit(&Outbox.attach/0)

    Store.setup(tags)
  end
end
