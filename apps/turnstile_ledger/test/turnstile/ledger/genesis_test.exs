defmodule Turnstile.Ledger.GenesisTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Genesis
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.Subject
  alias Turnstile.Test

  @repo TestRepos.App
  @schemas [Account, Folder, Turnstile.Fixture.Membership]
  @migration Turnstile.Ledger.TestMigrations.Events

  setup tags do
    {:ok, context} = Boot.setup(tags)
    {:ok, Keyword.put(context, :tables, before_the_ledger())}
  end

  test "genesis writes every current fact at position zero, stamped with the date and the migration", context do
    assert {:ok, 3} = Genesis.run(options(context), @schemas, migration: @migration)

    events = read(context)
    assert Enum.map(events, & &1.position) == [0, 0, 0]
    assert Enum.map(events, & &1.by) == List.duplicate(Subject.library(), 3)
    assert Enum.map(events, & &1.kind) == [:subject_attribute, :relationship, :relationship]
    assert Enum.uniq(Enum.map(events, & &1.operation_id)) == [Genesis.note(@migration, DateTime.utc_now())]
    assert {:ok, 0} = Ledger.Ecto.head(options(context))
  end

  test "the fold of a ledger that has only its genesis is the facts the tables held", context do
    {:ok, _count} = Genesis.run(options(context), @schemas, migration: @migration)
    folded = Ledger.Fold.fold(read(context))

    assert folded.facts == Ledger.Reconcile.facts(options(context), @schemas)
    assert folded.position == 0
  end

  test "genesis backfills the tables once and never beside events it did not write", context do
    {:ok, 3} = Genesis.run(options(context), @schemas, migration: @migration)

    assert {:error, %Error.Invalid{what: :genesis, detail: detail}} =
             Genesis.run(options(context), @schemas, migration: @migration)

    assert detail =~ "the ledger already holds 3 events"
  end

  test "genesis ignores a schema that declares no fact", context do
    assert {:ok, 1} = Genesis.run(options(context), [Folder, Account], migration: "0002")
  end

  test "genesis through a ledger that names no owner repo says why it cannot write", context do
    options = Keyword.delete(options(context), :owner_repo)

    assert_raise Error.Invalid, ~r/name no owner_repo/, fn ->
      Genesis.run(options, @schemas, migration: @migration)
    end
  end

  test "the stamp names the date the backfill ran and the migration that ran it" do
    assert Genesis.note(@migration, ~U[2026-09-08 12:00:00Z]) ==
             "backfilled from tables on 2026-09-08 by Turnstile.Ledger.TestMigrations.Events"

    assert Genesis.note("0002_ledger", ~U[2026-09-08 12:00:00Z]) == "backfilled from tables on 2026-09-08 by 0002_ledger"
  end

  # The tables as an application has them before the ledger exists: rows
  # written with no ledger configured, and so no event to describe them.
  defp before_the_ledger do
    Test.with_config([ledger: :none], fn ->
      [account] = Population.accounts!(@repo, 1)
      [folder] = Population.folders!(@repo, 1)
      1 = Population.memberships!(@repo, [account], folder)

      {:ok, _record} =
        Turnstile.Facts.bulk_update(Account, [set: [clearance: "cleared"]],
          repo: @repo,
          turnstile: Population.exemption()
        )

      1 = Population.memberships!(@repo, [account], folder)
      :ok
    end)
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options

  defp read(context) do
    {:ok, events} = Ledger.Reader.all({Ledger.Ecto, options(context)})
    events
  end
end
