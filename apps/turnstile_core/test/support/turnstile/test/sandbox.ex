defmodule Turnstile.Test.Sandbox do
  @moduledoc """
  Checks out a sandbox connection for the test process and shares it with
  processes the test spawns. Tests tagged `:committed` get no sandbox: they
  run real commits on the committed database and clean up through the owner repo.
  """

  alias Ecto.Adapters.SQL.Sandbox

  @doc "Call from `setup`. Returns `:ok`."
  @spec setup(module(), map()) :: :ok
  def setup(repo, tags) do
    if tags[:committed] do
      :ok
    else
      pid = Sandbox.start_owner!(repo, shared: not tags[:async])
      ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(pid) end)
      :ok
    end
  end
end
