defmodule Turnstile.FactsTripwireTest do
  use ExUnit.Case, async: false

  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Ledger
  alias Turnstile.Ledger.TestRepos.CommittedApp
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Measure
  alias Turnstile.Ledger.TestSupport.Population

  @moduletag :tripwire

  @repo CommittedApp
  @exemption Population.exemption()
  @rows 5_000
  @ceiling to_timeout(second: 10)

  setup tags do
    {:ok, context} = Boot.setup(tags)
    _accounts = Population.accounts!(@repo, @rows)
    {:ok, context}
  end

  test "a five thousand row fact write, events and all, inside ten seconds", context do
    started = System.monotonic_time(:millisecond)

    assert {:ok, record} =
             Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)

    elapsed = System.monotonic_time(:millisecond) - started

    Measure.report("\ntripwire: #{@rows} facts written in #{elapsed} ms, against a ceiling of #{@ceiling} ms")

    assert record.count == @rows
    assert elapsed < @ceiling
    assert {:ok, @rows} = Ledger.Ecto.head(options(context))
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options
end
