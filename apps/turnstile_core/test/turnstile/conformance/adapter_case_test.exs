defmodule Turnstile.Conformance.AdapterCaseTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Adapter.Fake,
    repo: Turnstile.TestRepos.Sandboxed,
    seed: Turnstile.Test.FakeSeed,
    outage: Turnstile.Test.FakeSeed,
    committed: [
      repo: Turnstile.TestRepos.Committed,
      owner: Turnstile.TestRepos.Owner,
      tables:
        ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders turnstile_fixture_accounts)
    ],
    projection: Turnstile.Test.Projection

  alias Ecto.Adapters.SQL
  alias Turnstile.Adapter.Fake
  alias Turnstile.Config
  alias Turnstile.Ledger.Memory
  alias Turnstile.Test.Projection
  alias Turnstile.TestRepos.Sandboxed

  setup %{ledger: ledger} do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    agent = start_supervised!(%{id: Projection, start: {Projection, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    {:ok, rules: rules, projection: %Projection{agent: agent, ledger: ledger}}
  end

  test "the setup binds the adapter, a memory ledger, the mock clock, and a per-test counter row", %{rules: rules} do
    assert {:ok, %Config{} = config} = Config.resolve()
    assert {Fake, options} = config.adapter
    assert options[:rules] == rules
    assert {Memory, ledger_options} = config.ledger
    assert is_pid(ledger_options[:agent])
    assert config.clock == Turnstile.Test.Clock.Mock
    assert %DateTime{} = config.clock.now()
    assert "test-" <> _rest = counter = config.ledger_counter

    assert %{rows: [[0]]} =
             SQL.query!(Sandboxed, "SELECT position FROM turnstile_ledger_counter WHERE name = $1", [counter])
  end
end

defmodule Turnstile.Conformance.AdapterCaseNoLedgerTest do
  use Turnstile.Conformance.AdapterCase,
    async: true,
    adapter: Turnstile.Adapter.Fake,
    repo: Turnstile.TestRepos.Sandboxed,
    ledger: :none,
    seed: Turnstile.Test.FakeSeed

  alias Turnstile.Adapter.Fake
  alias Turnstile.Config

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    :ok
  end

  test "the setup binds no ledger" do
    assert {:ok, %Config{ledger: :none}} = Config.resolve()
  end
end
