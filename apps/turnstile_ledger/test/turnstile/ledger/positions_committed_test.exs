defmodule Turnstile.Ledger.PositionsCommittedTest do
  use ExUnit.Case, async: false

  import Ecto.Query, only: [from: 2]

  alias Ecto.Adapters.SQL
  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Ledger
  alias Turnstile.Ledger.TestRepos.CommittedApp
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Measure
  alias Turnstile.Ledger.TestSupport.Population

  @moduletag :committed

  @repo CommittedApp
  @exemption Population.exemption()
  @writers 8

  setup tags do
    {:ok, context} = Boot.setup(tags)
    accounts = Population.accounts!(@repo, @writers)
    {:ok, Keyword.put(context, :accounts, accounts)}
  end

  test "two fact-writing transactions on one counter row take positions in commit order, and a reader from N skips none",
       context do
    {:ok, from} = Ledger.Ecto.head(options(context))
    [first_account, second_account | _rest] = context.accounts
    parent = self()
    first = Task.async(fn -> hold(parent, :first, first_account) end)

    assert_receive {:took, :first, first_position}, 2_000
    second = Task.async(fn -> hold(parent, :second, second_account) end)

    refute_receive {:took, :second, _position}, 200

    send(first.pid, :commit)
    assert :committed = Task.await(first)
    assert_receive {:took, :second, second_position}, 2_000
    send(second.pid, :commit)
    assert :committed = Task.await(second)

    assert {first_position, second_position} == {from + 1, from + 2}
    assert {:ok, events} = Ledger.Ecto.read(options(context), from, 10)
    assert Enum.map(events, & &1.position) == [from + 1, from + 2]
  end

  test "the cost of serializing on one counter row", context do
    started = System.monotonic_time(:microsecond)

    waits =
      context.accounts
      |> Task.async_stream(&timed_write(&1), max_concurrency: @writers, timeout: 30_000)
      |> Enum.map(fn {:ok, wait} -> wait end)

    elapsed = System.monotonic_time(:microsecond) - started

    Measure.report(
      "\nlock cost: #{@writers} fact-writing transactions on one counter row in #{elapsed} us, " <>
        "#{Float.round(@writers * 1_000_000 / elapsed, 1)} per second, " <>
        "mean #{div(Enum.sum(waits), @writers)} us each"
    )

    assert length(waits) == @writers
    assert {:ok, @writers} == Ledger.Ecto.head(options(context))
  end

  test "the application role may add an event and read one, and cannot change or remove one", context do
    {:ok, _record} = write(hd(context.accounts), "cleared")

    assert %{rows: [[1]]} = SQL.query!(@repo, "SELECT count(*) FROM turnstile_ledger_events")

    assert_raise Postgrex.Error, ~r/permission denied for table turnstile_ledger_events/, fn ->
      SQL.query!(@repo, "UPDATE turnstile_ledger_events SET attribute = 'other'")
    end

    assert_raise Postgrex.Error, ~r/permission denied for table turnstile_ledger_events/, fn ->
      SQL.query!(@repo, "DELETE FROM turnstile_ledger_events")
    end

    assert {:ok, 1} == Ledger.Ecto.head(options(context))
  end

  defp hold(parent, name, account) do
    fn ->
      {:ok, _record} = write(account, "cleared by #{name}")
      {:ok, position} = Ledger.Ecto.head(repo: @repo, owner_repo: @repo)
      send(parent, {:took, name, position})

      receive do
        :commit -> :committed
      end
    end
    |> @repo.transaction()
    |> then(fn {:ok, answer} -> answer end)
  end

  defp timed_write(account) do
    started = System.monotonic_time(:microsecond)
    {:ok, _record} = write(account, "cleared")
    System.monotonic_time(:microsecond) - started
  end

  defp write(account, clearance) do
    query = from(a in Account, where: a.id == ^account)
    Facts.bulk_update(query, [set: [clearance: clearance]], repo: @repo, turnstile: @exemption)
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options
end
