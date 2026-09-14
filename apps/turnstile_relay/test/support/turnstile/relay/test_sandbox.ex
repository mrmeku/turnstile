defmodule Turnstile.Relay.TestSandbox do
  @moduledoc """
  Checks out a sandbox connection for the test process and shares it with
  the processes the test spawns, so a runner started under a test reads and
  writes on the test's own connection. Tests tagged `:committed` get no
  sandbox: they run real commits on the committed database, which is where
  two connections can contend for a lock.

  This package holds no authorization concept, so there is nothing to seed
  here beyond the checkout.
  """

  use Boundary, top_level?: true, deps: [Ecto.Adapters.SQL]

  alias Ecto.Adapters.SQL.Sandbox

  @doc "Call from `setup`. Returns `:ok`."
  @spec setup(module(), map()) :: :ok
  def setup(repo, tags) when is_atom(repo) and is_map(tags) do
    if tags[:committed] do
      :ok
    else
      pid = Sandbox.start_owner!(repo, shared: not tags[:async])
      ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(pid) end)
      :ok
    end
  end
end
