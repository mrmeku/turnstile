defmodule Turnstile.FactsTest do
  use ExUnit.Case, async: true

  alias Ecto.Changeset
  alias Turnstile.Error
  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.Ledger.TestSupport.Shape
  alias Turnstile.Object
  alias Turnstile.Subject
  alias Turnstile.Test

  @repo TestRepos.App
  @exemption Population.exemption()
  @batch 2_000
  @subject %Subject{id: "11111111-1111-1111-1111-111111111111", kind: :user}

  setup tags do
    :ok = Shape.listen()
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

  test "a bulk write that touches no fact field is one query, with nothing returned and no event" do
    _folders = Population.folders!(@repo, 1_000)

    {result, queries} =
      Test.queries(@repo, fn ->
        Facts.bulk_update(Folder, [set: [name: "renamed"]], repo: @repo, turnstile: @exemption)
      end)

    assert {:ok, record} = result
    assert Shape.kinds(queries) == [:update]
    refute Enum.any?(queries, &String.contains?(&1, "RETURNING"))
    assert Shape.records(record.operation_id) == [record]
    assert {record.count, record.min_position, record.max_position} == {1_000, nil, nil}
    assert read() == []
  end

  test "a bulk_update of a fact field on 5,000 rows is one update, one take, three inserts, and 5,000 events" do
    rows = 5_000
    _accounts = Population.accounts!(@repo, rows)

    {result, queries} =
      Test.queries(@repo, fn ->
        Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
      end)

    assert {:ok, record} = result
    assert Shape.kinds(queries) == [:locked_select, :update, :take, :events, :events, :events]
    assert Shape.records(record.operation_id) == [record]
    assert {record.count, record.min_position, record.max_position} == {rows, 1, rows}
    events = read()
    assert length(events) == rows
    assert Enum.map(events, & &1.operation_id) == List.duplicate(record.operation_id, rows)
    assert div(rows - 1, @batch) + 1 == 3
  end

  test "a bulk_update of a fact field to the value the rows hold writes no event and takes no position" do
    _accounts = Population.accounts!(@repo, 1_000)
    {:ok, _first} = Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
    before = Ledger.Ecto.count(@repo)

    {result, queries} =
      Test.queries(@repo, fn ->
        Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
      end)

    assert {:ok, record} = result
    assert Shape.kinds(queries) == [:locked_select, :update]
    assert Shape.records(record.operation_id) == [record]
    assert {record.count, record.min_position} == {0, nil}
    assert Ledger.Ecto.count(@repo) == before
  end

  test "a ledger append that fails rolls the bulk write back and answers an engine error" do
    [id] = Population.accounts!(@repo, 1)
    Test.with_config(ledger_counter: "missing")

    assert {:error, %Error.Engine{operation: :take}} =
             Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)

    assert @repo.get!(Account, id, turnstile: @exemption).clearance == nil
  end

  test "a ledger append that fails rolls a single-row fact write back" do
    account = one_account()
    Test.with_config(ledger_counter: "missing")

    assert_raise Error.Engine, fn ->
      @repo.update!(Changeset.change(account, clearance: "cleared"), turnstile: @exemption)
    end

    assert @repo.get!(Account, account.id, turnstile: @exemption).clearance == nil
  end

  test "a bulk_insert of relationship rows records the grant of every row, and a bulk_delete records its end" do
    [account] = Population.accounts!(@repo, 1)
    [folder] = Population.folders!(@repo, 1)
    before = Ledger.Ecto.count(@repo)

    assert 1 == Population.memberships!(@repo, [account], folder)
    assert [grant] = Enum.drop(read(), before)
    assert {grant.kind, grant.old, grant.new} == {:relationship, nil, :reader}

    assert {:ok, record} = Facts.bulk_delete(Membership, repo: @repo, turnstile: @exemption)
    assert record.count == 1
    assert [_grant, revocation] = Enum.drop(read(), before)
    assert {revocation.kind, revocation.old, revocation.new} == {:relationship, :reader, nil}
  end

  test "the bulk API needs a dialect whose write returns the rows it wrote" do
    _accounts = Population.accounts!(@repo, 1)
    Test.with_config(ledger: {Ledger.Ecto, ledger_options(dialect: Turnstile.Ledger.TestSupport.Dialect)})

    assert_raise Error.Unsupported, ~r/answers :select/, fn ->
      Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
    end
  end

  test "a bulk write with no repo in the options and none in the ledger's says which option is missing" do
    Test.with_config(ledger: :none)

    assert_raise Error.Invalid, ~r/needs repo: MyApp.Repo/, fn ->
      Facts.bulk_update(Account, [set: [clearance: "cleared"]], turnstile: @exemption)
    end
  end

  test "a bulk write on something that is not a schema or a query on one is refused" do
    assert_raise Error.Invalid, ~r/needs a schema or a query on one/, fn ->
      Facts.bulk_update("turnstile_fixture_accounts", [set: [clearance: "x"]], repo: @repo, turnstile: @exemption)
    end
  end

  test "the three telemetry events of a bulk write are the span's three suffixes" do
    assert Facts.events() == [
             [:turnstile, :bulk, :start],
             [:turnstile, :bulk, :stop],
             [:turnstile, :bulk, :exception]
           ]
  end

  defp one_account do
    [id] = Population.accounts!(@repo, 1)
    @repo.get!(Account, id, turnstile: @exemption)
  end

  defp decision(id) do
    Test.with_config(adapter: {Turnstile.Adapter.Fake, verdict: :allow})
    {:ok, decision} = Turnstile.authorize(@subject, :edit, %Object{type: :account, id: id})
    decision
  end

  defp read do
    {:ok, events} = Ledger.Reader.all({Ledger.Ecto, ledger_options()})
    events
  end

  defp ledger_options(extra \\ []) do
    {:ok, config} = Turnstile.Config.resolve()
    {Ledger.Ecto, options} = config.ledger
    Keyword.merge(options, extra)
  end
end
