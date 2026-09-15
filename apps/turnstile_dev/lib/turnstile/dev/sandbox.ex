defmodule Turnstile.Dev.Sandbox do
  @moduledoc """
  Checks out a sandbox connection for the test process and shares it with
  processes the test spawns, so a test that writes sees its own rows and
  nobody else's. Tests tagged `:committed` get no sandbox: they run real
  commits on the committed database.
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
    end
  end
end
