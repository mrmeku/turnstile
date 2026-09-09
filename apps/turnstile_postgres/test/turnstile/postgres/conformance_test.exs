defmodule Turnstile.Postgres.ConformanceTest do
  use Turnstile.Conformance.AdapterCase,
    adapter: Turnstile.Postgres,
    repo: Turnstile.TestRepos.Sandboxed,
    async: false,
    setup_queries: 1,
    outage: Turnstile.Postgres.ConformanceTest.Unreachable,
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

  alias Turnstile.Postgres.Binding

  defmodule Stopped do
    @moduledoc "A repo that is configured nowhere and started never, so every statement through it raises."

    use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
    use Turnstile.Repo
  end

  defmodule Unreachable do
    @moduledoc "The outage: the database is out of reach for the rest of the test."

    @doc "Point the binding at the stopped repo, so the first statement any callback runs raises."
    @spec outage() :: :ok
    def outage, do: Binding.override(repo: Stopped)
  end

  # The template hands each test the repo of its tier, so the binding is
  # made per test rather than at boot: the sandboxed tier and the committed
  # tier read the same policies through different connections.
  setup %{repo: repo} do
    :ok =
      Binding.override(
        repo: repo,
        schemas: [
          Turnstile.Fixture.Account,
          Turnstile.Fixture.Folder,
          Turnstile.Fixture.Item,
          Turnstile.Fixture.Membership
        ]
      )

    :ok
  end
end
