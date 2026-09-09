defmodule Turnstile.Ledger.ReconcileCommittedTest do
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL
  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Reconcile
  alias Turnstile.Ledger.TestRepos.CommittedApp
  alias Turnstile.Ledger.TestRepos.CommittedOwner
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.Projection.Drift

  @moduletag :committed

  @repo CommittedApp
  @exemption Population.exemption()
  @schemas [Account, Folder, Membership]

  setup tags do
    {:ok, context} = Boot.setup(tags)
    [account] = Population.accounts!(@repo, 1)
    {:ok, _record} = Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
    {:ok, Keyword.put(context, :account, account)}
  end

  test "a write that another connection committed behind the seam is drift", context do
    assert {:ok, drift} = Reconcile.run(options(context), @schemas)
    assert Drift.clean?(drift)

    %{num_rows: 1} = SQL.query!(CommittedOwner, "UPDATE turnstile_fixture_accounts SET clearance = 'patched'")

    assert {:ok, %Drift{} = drift} = Reconcile.run(options(context), @schemas)
    refute Drift.clean?(drift)
    assert drift.missing == [{{{:user, context.account}, nil, :clearance}, "cleared"}]
    assert drift.extra == [{{{:user, context.account}, nil, :clearance}, "patched"}]
    assert {:ok, drift.checked_to} == Ledger.Ecto.head(options(context))
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options
end
