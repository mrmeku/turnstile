defmodule Turnstile.Fga.ConformanceTest do
  use Turnstile.Conformance.AdapterCase,
    adapter: Turnstile.Fga,
    repo: Turnstile.TestRepos.Sandboxed,
    async: false,
    setup_queries: 1,
    seed: Turnstile.Fga.Seed,
    outage: Turnstile.Fga.ConformanceTest.Unreachable,
    committed: [
      repo: Turnstile.TestRepos.Committed,
      owner: Turnstile.TestRepos.Owner,
      tables: [
        "turnstile_fixture_memberships",
        "turnstile_fixture_items",
        "turnstile_fixture_folders",
        "turnstile_fixture_accounts"
      ]
    ],
    projection: Turnstile.Fga.Projected

  alias Turnstile.FactEvent
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Model
  alias Turnstile.Fga.Projector
  alias Turnstile.PolicyVersion
  alias Turnstile.Test

  @model "priv/conformance/model.fga"

  defmodule Unreachable do
    @moduledoc "The outage: the server is out of reach for the rest of the test."

    alias Turnstile.Config

    @doc "Point the configuration at a port nothing listens on, keeping the store and the model it pins."
    @spec outage() :: :ok
    def outage do
      {:ok, config} = Config.resolve()
      {Fga, options} = Config.adapter(config)

      Test.with_config(adapter: {Fga, Keyword.put(options, :endpoint, "127.0.0.1:1")})
    end
  end

  # A store per test on the run's server, and the model published into it as
  # a policy version, so the id every question is pinned to is the id the
  # ledger records. The template hands each test the repo of its tier, so the
  # binding is made per test as well: the checkpoint is read where that tier's
  # tables are.
  #
  # The three projection cases drive a store of their own, empty and with no
  # checkpoint row, because they are about a drain that starts at zero and one
  # that is interrupted with work still to do. The serving store is the one the
  # seed drains into, which is what every decision case reads.
  setup %{repo: repo} do
    server = Test.Fga.info()
    {:ok, store} = Http.create_store(server.address, name())
    :ok = Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store})
    :ok = Binding.override(repo: repo, model: @model, mapping: Mapping, author: "conformance", approval: "conformance")
    assert {:ok, %FactEvent{new: %PolicyVersion{version: model}}} = Fga.publish()
    :ok = Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store, model_id: model})

    {:ok, projection: projection(server.address)}
  end

  # The store the projection cases drain into carries the same model, since a
  # write is validated against the model the store has published.
  defp projection(address) do
    {:ok, store} = Http.create_store(address, name())
    {:ok, _model} = Http.write_model(address, store, Model.read!(@model))
    {:ok, projector} = Projector.resolve(Fga)

    %{projector | store: store}
  end

  defp name, do: "conformance-#{System.unique_integer([:positive])}"
end
