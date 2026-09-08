defmodule Turnstile.Code.ConformanceTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Code,
    repo: Turnstile.TestRepos.Sandboxed,
    committed: [
      repo: Turnstile.TestRepos.Committed,
      owner: Turnstile.TestRepos.Owner,
      tables:
        ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders turnstile_fixture_accounts)
    ]

  alias Turnstile.Code.Binding
  alias Turnstile.Code.Conformance.Roles

  setup %{repo: repo} do
    :ok = Binding.override(policy: Roles, repo: repo)
  end
end
