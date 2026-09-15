defmodule Turnstile.Rbac.ConformanceTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Rbac,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Dev.Sandbox,
    committed: [
      repo: Turnstile.TestRepos.Committed,
      owner: Turnstile.TestRepos.Owner,
      tables:
        ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders turnstile_fixture_accounts)
    ],
    versions: Turnstile.Rbac.Conformance.Versions

  alias Turnstile.Rbac.Binding
  alias Turnstile.Rbac.Conformance.Roles

  setup %{repo: repo} do
    :ok = Binding.override(policy: Roles, repo: repo)
  end
end
