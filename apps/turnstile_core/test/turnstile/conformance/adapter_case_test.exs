defmodule Turnstile.Conformance.AdapterCaseTest do
  use Turnstile.Conformance.AdapterCase,
    adapter: Turnstile.Adapter.Fake,
    repo: Turnstile.TestRepos.Sandboxed,
    async: true

  alias Ecto.Adapters.SQL
  alias Turnstile.Adapter.Fake
  alias Turnstile.Config
  alias Turnstile.TestRepos.Sandboxed

  test "the setup binds the adapter and a per-test counter row through the override", %{adapter: adapter} do
    assert adapter == Fake
    Turnstile.Test.with_config(ledger: :none)
    assert {:ok, %Config{adapter: {Fake, verdict: :deny}, ledger_counter: "test-" <> _rest = counter}} = Config.resolve()

    assert %{rows: [[0]]} =
             SQL.query!(Sandboxed, "SELECT position FROM turnstile_ledger_counter WHERE name = $1", [
               counter
             ])
  end
end
