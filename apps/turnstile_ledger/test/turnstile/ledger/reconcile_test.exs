defmodule Turnstile.Ledger.ReconcileTest do
  use ExUnit.Case, async: true

  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Reconcile
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.Projection.Drift
  alias Turnstile.Test

  @repo TestRepos.App
  @exemption Population.exemption()
  @schemas [Account, Folder, Membership]
  @unrecorded "account-90001"

  setup tags do
    {:ok, context} = Boot.setup(tags)
    [account] = Population.accounts!(@repo, 1)
    [folder] = Population.folders!(@repo, 1)
    1 = Population.memberships!(@repo, [account], folder)
    1 = Population.clearance!(@repo, [account], "cleared")
    {:ok, Keyword.merge(context, account: account, folder: folder)}
  end

  test "a ledger that recorded every fact write agrees with the tables", context do
    assert {:ok, %Drift{} = drift} = Reconcile.run(options(context), @schemas)
    assert Drift.clean?(drift)
    assert {drift.missing, drift.extra} == {[], []}
    assert {:ok, drift.checked_to} == Ledger.Ecto.head(options(context))
  end

  test "a fact the tables lost outside the seam is missing", context do
    Test.with_config([ledger: :none], fn ->
      grant = @repo.get_by!(Membership, [account_id: context.account, folder_id: context.folder], turnstile: @exemption)
      %Membership{} = @repo.delete!(grant, turnstile: @exemption)
    end)

    assert {:ok, drift} = Reconcile.run(options(context), @schemas)
    refute Drift.clean?(drift)
    assert drift.missing == [{{{:user, context.account}, {:folder, context.folder}, nil}, :reader}]
    assert drift.extra == []
  end

  test "a fact the tables gained outside the seam is extra", context do
    Test.with_config([ledger: :none], fn ->
      %Account{} = @repo.insert!(%Account{id: @unrecorded, clearance: "raised"}, turnstile: @exemption)
    end)

    assert {:ok, drift} = Reconcile.run(options(context), @schemas)
    refute Drift.clean?(drift)
    assert drift.missing == []
    assert drift.extra == [{{{:user, @unrecorded}, nil, :clearance}, "raised"}]
  end

  test "the facts a schema that declares none holds are no facts at all", context do
    assert Reconcile.facts(options(context), [Folder]) == %{}
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options
end
