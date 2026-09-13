defmodule Turnstile.Ledger.WritesTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Turnstile.Error
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.Ledger.TestSupport.Shape
  alias Turnstile.Test

  @repo TestRepos.App
  @exemption Population.exemption()
  @subject {:user, "11111111-1111-1111-1111-111111111111"}

  setup tags do
    Boot.setup(tags)
  end

  test "a mediated single-row fact write is the re-read, the write, the counter take, and one ledger insert" do
    account = one_account()
    decision = decision(account.id)

    {_row, queries} =
      Test.queries(@repo, fn ->
        @repo.update!(Changeset.change(account, clearance: "cleared"), turnstile: decision)
      end)

    assert Shape.kinds(queries) == [:locked_select, :update, :take, :events]
    assert Ledger.Ecto.count(@repo) == 1
    assert [event] = read()
    assert event.operation_id == decision.operation_id
    assert event.by == decision.subject
    assert {event.old, event.new} == {nil, "cleared"}
  end

  test "the same single-row fact write in mode none is the write alone" do
    account = one_account()
    decision = decision(account.id)
    before = Ledger.Ecto.count(@repo)
    Test.with_config(ledger: :none)

    {_row, queries} =
      Test.queries(@repo, fn ->
        @repo.update!(Changeset.change(account, clearance: "cleared"), turnstile: decision)
      end)

    assert Shape.kinds(queries) == [:update]
    assert Ledger.Ecto.count(@repo) == before
  end

  test "a ledger append that fails rolls a single-row fact write back" do
    account = one_account()
    Test.with_config(ledger_counter: "missing")

    assert_raise Error, ~r/failed during take/, fn ->
      @repo.update!(Changeset.change(account, clearance: "cleared"), turnstile: @exemption)
    end

    assert @repo.get!(Account, account.id, turnstile: @exemption).clearance == nil
  end

  test "a relationship row records the grant it is, and its deletion records the end of it" do
    [account] = Population.accounts!(@repo, 1)
    [folder] = Population.folders!(@repo, 1)
    before = Ledger.Ecto.count(@repo)

    assert 1 == Population.memberships!(@repo, [account], folder)
    assert [grant] = Enum.drop(read(), before)
    assert {grant.kind, grant.old, grant.new} == {:relationship, nil, :reader}

    membership = @repo.get_by!(Membership, [account_id: account, folder_id: folder], turnstile: @exemption)
    assert %Membership{} = @repo.delete!(membership, turnstile: @exemption)
    assert [_grant, revocation] = Enum.drop(read(), before)
    assert {revocation.kind, revocation.old, revocation.new} == {:relationship, :reader, nil}
  end

  defp one_account do
    [id] = Population.accounts!(@repo, 1)
    @repo.get!(Account, id, turnstile: @exemption)
  end

  defp decision(id) do
    Test.with_config(adapter: {Turnstile.Test.Fake, verdict: :allow})
    {:ok, decision} = Turnstile.authorize(@subject, :edit, {:account, id})
    decision
  end

  defp read do
    {:ok, config} = Turnstile.Config.resolve()
    {:ok, events} = Ledger.Reader.all(config.ledger)
    events
  end
end
