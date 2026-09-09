defmodule Turnstile.FactsPropertyTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  import Ecto.Query, only: [where: 3]

  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Reconcile
  alias Turnstile.Ledger.Replay
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population

  @repo TestRepos.App
  @exemption Population.exemption()
  @schemas [Account, Membership, Turnstile.Fixture.Folder]

  setup tags do
    {:ok, context} = Boot.setup(tags)
    accounts = Population.accounts!(@repo, 3)
    folders = Population.folders!(@repo, 2)
    {:ok, Keyword.merge(context, accounts: accounts, folders: folders)}
  end

  property "the fold of what the bulk API wrote is what the tables hold, and a replay to the head is that fold",
           context do
    check all(steps <- list_of(step(context), min_length: 1, max_length: 6), max_runs: 15) do
      Enum.each(steps, &apply_step/1)

      folded = Ledger.Fold.fold(events())
      assert folded.facts == Reconcile.facts(options(), @schemas)

      {:ok, head} = Ledger.Ecto.head(options())
      assert {:ok, replay} = Replay.to({Ledger.Ecto, options()}, head)
      assert replay.fold.facts == folded.facts
      assert replay.position == head
      assert Replay.positioned?(replay) == head > 0

      assert {:ok, at} = Replay.at({Ledger.Ecto, options()}, DateTime.utc_now())
      assert at.fold.facts == folded.facts
    end
  end

  defp step(context) do
    account = member_of(context.accounts)
    folder = member_of(context.folders)

    one_of([
      tuple({constant(:clearance), account, member_of(["cleared", nil])}),
      tuple({constant(:grant), account, folder, member_of([:reader, :editor])}),
      tuple({constant(:revoke), account, folder})
    ])
  end

  defp apply_step({:clearance, account, value}) do
    query = where(Account, [a], a.id == ^account)
    {:ok, _record} = Facts.bulk_update(query, [set: [clearance: value]], options(:write))
  end

  defp apply_step({:grant, account, folder, role}) do
    {:ok, _revoked} = Facts.bulk_delete(membership(account, folder), options(:write))
    entries = [%{account_id: account, folder_id: folder, role: role}]
    {:ok, _granted} = Facts.bulk_insert(Membership, entries, options(:write))
  end

  defp apply_step({:revoke, account, folder}) do
    {:ok, _record} = Facts.bulk_delete(membership(account, folder), options(:write))
  end

  defp membership(account, folder) do
    where(Membership, [m], m.account_id == ^account and m.folder_id == ^folder)
  end

  defp events do
    {:ok, events} = Ledger.Reader.all({Ledger.Ecto, options()})
    events
  end

  defp options(:write), do: [repo: @repo, turnstile: @exemption]

  defp options do
    {:ok, config} = Turnstile.Config.resolve()
    {Ledger.Ecto, options} = config.ledger
    options
  end
end
