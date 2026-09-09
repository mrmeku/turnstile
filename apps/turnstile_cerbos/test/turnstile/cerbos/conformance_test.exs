defmodule Turnstile.Cerbos.ConformanceTest do
  use Turnstile.Conformance.AdapterCase,
    adapter: Turnstile.Cerbos,
    repo: Turnstile.TestRepos.Sandboxed,
    async: false,
    setup_queries: 1,
    outage: Turnstile.Cerbos.ConformanceTest.Unreachable,
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

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Conformance.Attributes
  alias Turnstile.Test

  defmodule Unreachable do
    @moduledoc "The outage: the sidecar is out of reach for the rest of the test."

    @doc "Point the configuration at a port nothing listens on, so every call fails to connect."
    @spec outage() :: :ok
    def outage, do: Test.with_config(adapter: {Turnstile.Cerbos, address: "127.0.0.1:1"})
  end

  # The template hands each test the repo of its tier, so the binding is
  # made per test: both tiers ask the run's sidecar, which answers from the
  # policies in the repository, and read their facts through their own
  # connection.
  setup %{repo: repo} do
    sidecar = Test.Cerbos.info()
    :ok = Test.with_config(adapter: {Turnstile.Cerbos, address: sidecar.address})

    Binding.override(
      repo: repo,
      attributes: Attributes,
      policies: sidecar.policies,
      commit: "conformance",
      decision_log: sidecar.audit_log
    )
  end
end
