defmodule Turnstile.Fga.ConformanceTest do
  use Turnstile.Conformance.AdapterCase,
    adapter: Turnstile.Fga,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Test.Sandbox,
    async: false,
    setup_queries: 0,
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
    ]

  alias Turnstile.Dev
  alias Turnstile.FactEvent
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Conformance.Mapping
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
  # binding is made per test as well: the markers and the tables the drain
  # reads are that tier's.
  setup %{repo: repo} do
    server = Dev.Fga.info()
    {:ok, store} = Http.create_store(server.address, name())
    :ok = Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store})
    :ok = Binding.override(repo: repo, model: @model, mapping: Mapping, author: "conformance", approval: "conformance")
    assert {:ok, %FactEvent{new: %PolicyVersion{version: model}}} = Fga.publish()
    Test.with_config(adapter: {Fga, endpoint: server.address, store_id: store, model_id: model})
  end

  defp name, do: "conformance-#{System.unique_integer([:positive])}"
end
