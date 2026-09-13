defmodule Turnstile.Test.Sandbox do
  @moduledoc """
  Checks out a sandbox connection for the test process, shares it with
  processes the test spawns, inserts the test's own counter row inside the
  sandbox transaction, and points the configuration override at it, so async
  fact-writing tests never contend on `default`. Tests tagged `:committed`
  get no sandbox and no row: they run real commits on the committed database
  and use `default`.
  """

  use Boundary, top_level?: true, deps: [Turnstile.Test, Ecto.Adapters.SQL]

  alias Ecto.Adapters.SQL.Sandbox

  @doc "Call from `setup`. Returns `:ok`."
  @spec setup(module(), map()) :: :ok
  def setup(repo, tags) when is_atom(repo) and is_map(tags) do
    if tags[:committed] do
      :ok
    else
      pid = Sandbox.start_owner!(repo, shared: not tags[:async])
      ExUnit.Callbacks.on_exit(fn -> Sandbox.stop_owner(pid) end)
      counter = "test-" <> Integer.to_string(System.unique_integer([:positive]))

      {1, nil} =
        repo.insert_all("turnstile_ledger_counter", [%{name: counter, position: 0}], turnstile: {:exempt, :library})

      Turnstile.Test.with_config(ledger_counter: counter)
    end
  end
end
