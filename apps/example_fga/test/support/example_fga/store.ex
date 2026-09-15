defmodule ExampleFga.Store do
  @moduledoc """
  A store of each test's own, with the boot model written into it and
  pinned for the calling process.

  The store is per test because it is the engine's own copy of the facts: two
  tests writing tuples into one store would read each other's, whatever the
  database does with their rows. Creating it is what `setup/1` is for, and the
  boot model is written into it there, so every question the test asks is
  asked under a model of its own.
  """

  use Boundary, top_level?: true, deps: [ExampleFga, Turnstile, Turnstile.Fga, Turnstile.Test]

  alias Turnstile.Dev
  alias Turnstile.Fga
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Model
  alias Turnstile.Test

  @doc "Create the store, bind the calling process to it, and pin the boot model in it."
  @spec setup(map()) :: :ok
  def setup(_tags) do
    server = Dev.Fga.info()
    {:ok, store} = Http.create_store(server.address, name())
    {:ok, model} = Http.write_model(server.address, store, Model.read!(ExampleFga.model()))
    Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store, model_id: model})
  end

  defp name, do: "example-fga-#{System.unique_integer([:positive])}"
end
