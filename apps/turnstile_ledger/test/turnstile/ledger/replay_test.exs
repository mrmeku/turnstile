defmodule Turnstile.Ledger.ReplayTest.OtherAdapter do
  @moduledoc "A second adapter, so a replay narrowed to one adapter has two published versions to choose between."
end

defmodule Turnstile.Ledger.ReplayTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Turnstile.Adapter
  alias Turnstile.FactEvent
  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Genesis
  alias Turnstile.Ledger.Replay
  alias Turnstile.Ledger.ReplayTest.OtherAdapter
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject
  alias Turnstile.Test

  @subject {:user, "11111111-1111-1111-1111-111111111111"}
  @key {@subject, nil, :clearance}
  @early ~U[2026-09-08 09:00:00.000000Z]
  @late ~U[2026-09-08 17:00:00.000000Z]

  setup tags do
    Boot.setup(tags)
  end

  test "a replay to a position answers the facts as of that position and the version published latest below it",
       context do
    :ok = history(context)

    assert {:ok, replay} = Replay.to(ledger(context), 2)
    assert replay.fold.facts == %{@key => "confidential"}
    assert replay.policy_version.version == "one"
    assert {replay.position, replay.at} == {2, @early}
    assert Replay.positioned?(replay)

    assert {:ok, whole} = Replay.to(ledger(context), 4)
    assert whole.fold.facts == %{@key => "secret"}
    assert whole.policy_version.version == "two"
  end

  test "a replay narrowed to an adapter answers the version that adapter published, not another's", context do
    :ok = history(context)

    assert {:ok, narrowed} = Replay.to(ledger(context), 4, adapter: Adapter.Fake)
    assert narrowed.policy_version.version == "one"
    assert narrowed.policy_version.adapter == Adapter.Fake

    assert {:ok, other} = Replay.to(ledger(context), 4, adapter: OtherAdapter)
    assert other.policy_version.version == "two"
  end

  test "a replay to a date answers the facts as they were stamped at or before it", context do
    :ok = history(context)

    assert {:ok, replay} = Replay.at(ledger(context), @early, adapter: Adapter.Fake)
    assert replay.fold.facts == %{@key => "confidential"}
    assert replay.policy_version.version == "one"
    assert {replay.position, replay.at} == {2, @early}

    assert {:ok, later} = Replay.at(ledger(context), @late)
    assert later.fold.facts == %{@key => "secret"}
    assert later.policy_version.version == "two"
  end

  test "a replay of a ledger that holds nothing but its backfill reproduces the backfill and is not positioned",
       context do
    Test.with_config(ledger_counter: "genesis-only")
    %{num_rows: 1} = SQL.query!(TestRepos.App, insert(), ["genesis-only"])
    account = before_the_ledger()

    {:ok, 1} = Genesis.run(options(context), [Account], migration: __MODULE__)

    assert {:ok, replay} = Replay.to(ledger(context), 0)
    assert replay.fold.facts == %{{{:user, account}, nil, :clearance} => "cleared"}
    assert replay.position == 0
    refute Replay.positioned?(replay)
  end

  defp history(context) do
    {:ok, _events} =
      Ledger.Ecto.append(options(context), [
        clearance(nil, "confidential", @early),
        published(Adapter.Fake, "one", @early),
        clearance("confidential", "secret", @late),
        published(OtherAdapter, "two", @late)
      ])

    :ok
  end

  defp before_the_ledger do
    Test.with_config([ledger: :none], fn ->
      [account] = Population.accounts!(TestRepos.App, 1)

      {:ok, _record} =
        Facts.bulk_update(Account, [set: [clearance: "cleared"]],
          repo: TestRepos.App,
          turnstile: Population.exemption()
        )

      account
    end)
  end

  defp insert, do: "INSERT INTO turnstile_ledger_counter (name, position) VALUES ($1, 0)"

  defp ledger(context), do: {Ledger.Ecto, options(context)}

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options

  defp clearance(old, new, at) do
    %FactEvent{
      kind: :subject_attribute,
      subject_ref: @subject,
      object_ref: nil,
      attribute: :clearance,
      old: old,
      new: new,
      position: nil,
      operation_id: "22222222-2222-2222-2222-222222222222",
      at: at,
      by: Subject.library()
    }
  end

  defp published(adapter, version, at) do
    published = %PolicyVersion{
      adapter: adapter,
      version: version,
      content_hash: "sha256-" <> version,
      content: "allow nothing",
      author: "an author",
      approval: "a change ticket",
      at: at
    }

    %{clearance(nil, nil, at) | kind: :policy_version, subject_ref: nil, attribute: nil, new: published}
  end
end
