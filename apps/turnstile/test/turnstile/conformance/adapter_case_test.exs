defmodule Turnstile.Conformance.AdapterCaseTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Test.Fake,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Dev.Sandbox,
    seed: Turnstile.Test.FakeSeed,
    outage: Turnstile.Test.FakeSeed,
    committed: [
      repo: Turnstile.TestRepos.Committed,
      owner: Turnstile.TestRepos.Owner,
      tables:
        ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders turnstile_fixture_accounts)
    ]

  alias Turnstile.Config
  alias Turnstile.Test.Fake

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    {:ok, rules: rules}
  end

  test "the setup binds the adapter and the clock", %{rules: rules} do
    assert {:ok, %Config{} = config} = Config.resolve()
    assert {Fake, options} = config.adapter
    assert options[:rules] == rules
    assert %DateTime{} = config.clock.()
  end
end

defmodule Turnstile.Conformance.AdapterCaseSettlingTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Test.SettlingAdapter,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Dev.Sandbox,
    seed: Turnstile.Test.FakeSeed

  alias Turnstile.Test.Fake
  alias Turnstile.Test.SettlingAdapter

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {SettlingAdapter, rules: rules})
    :ok
  end

  test "the adapter this module runs has state of its own to settle" do
    assert function_exported?(SettlingAdapter, :settle, 0)
  end
end
