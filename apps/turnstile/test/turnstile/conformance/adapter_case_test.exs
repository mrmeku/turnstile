defmodule Turnstile.Conformance.AdapterCaseTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Test.Fake,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Test.Sandbox,
    seed: Turnstile.Test.FakeSeed,
    outage: Turnstile.Test.FakeSeed,
    committed: [
      repo: Turnstile.TestRepos.Committed,
      owner: Turnstile.TestRepos.Owner,
      tables:
        ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders turnstile_fixture_accounts)
    ]

  alias Ecto.Adapters.SQL
  alias Turnstile.Config
  alias Turnstile.Ledger.Memory
  alias Turnstile.Test.Fake
  alias Turnstile.TestRepos.Sandboxed

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    {:ok, rules: rules}
  end

  test "the setup binds the adapter, a memory ledger, the clock, and a per-test counter row", %{rules: rules} do
    assert {:ok, %Config{} = config} = Config.resolve()
    assert {Fake, options} = config.adapter
    assert options[:rules] == rules
    assert {Memory, ledger_options} = config.ledger
    assert is_pid(ledger_options[:agent])
    assert %DateTime{} = config.clock.()
    assert "test-" <> _rest = counter = config.ledger_counter

    assert %{rows: [[0]]} =
             SQL.query!(Sandboxed, "SELECT position FROM turnstile_ledger_counter WHERE name = $1", [counter])
  end
end

defmodule Turnstile.Conformance.AdapterCaseNoLedgerTest do
  use Turnstile.Conformance.AdapterCase,
    async: true,
    adapter: Turnstile.Test.Fake,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Test.Sandbox,
    ledger: :none,
    seed: Turnstile.Test.FakeSeed

  alias Turnstile.Config
  alias Turnstile.Test.Fake

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    :ok
  end

  test "the setup binds no ledger" do
    # Not async: the worlds of this module and of the mode-none one are the
    # same rows of the same tables, and two of them written at once deadlock.
    assert {:ok, %Config{ledger: :none}} = Config.resolve()
  end
end

defmodule Turnstile.Conformance.AdapterCaseLedgerTest do
  use Turnstile.Conformance.AdapterCase,
    async: false,
    adapter: Turnstile.Test.LedgerAdapter,
    repo: Turnstile.TestRepos.Sandboxed,
    world: Turnstile.Fixture.World,
    sandbox: Turnstile.Test.Sandbox,
    seed: Turnstile.Test.FakeSeed

  alias Turnstile.Test.Fake
  alias Turnstile.Test.LedgerAdapter

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Turnstile.Test.with_config(adapter: {LedgerAdapter, rules: rules})
    :ok
  end

  test "the adapter this module runs requires a ledger, which is what the shape cases branch on" do
    assert LedgerAdapter.requires_ledger()
  end
end
