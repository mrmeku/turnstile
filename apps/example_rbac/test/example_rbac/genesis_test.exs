defmodule ExampleRbac.GenesisTest do
  # Not async: the backfill reads the tables outside a sandbox and refuses to
  # run beside events it did not write, so it needs the committed database
  # and the events table to itself.
  use ExUnit.Case, async: false

  alias Ecto.Adapters.SQL.Sandbox
  alias Example.Fixture
  alias Example.Fixture.Clock
  alias Example.OwnerRepo
  alias Example.User
  alias Turnstile.Ledger.Genesis
  alias Turnstile.Ledger.Reader

  @moduletag :needs_ledger

  @at ~U[2026-03-04 05:06:07.000000Z]

  setup do
    :ok = Sandbox.checkout(Example.Repo, sandbox: false)
    :ok = Fixture.truncate!(OwnerRepo)
    on_exit(fn -> Fixture.truncate!(OwnerRepo) end)
    :ok
  end

  test "the backfill writes the facts the tables already hold at position zero, stamped with its date and migration" do
    _user =
      OwnerRepo.insert!(%User{
        id: "zoe",
        name: "zoe",
        kind: :user,
        person_id: "zoe",
        employment: :federal,
        nationality: "US"
      })

    :ok = Clock.set(@at)
    assert {:ok, 2} = Genesis.run(options(), Example.schemas(), migration: __MODULE__, clock: Clock)

    assert {:ok, events} = Reader.all(ledger())
    assert Enum.map(events, & &1.attribute) == [:employment, :nationality]
    assert Enum.map(events, & &1.new) == [:federal, "US"]

    for event <- events do
      assert event.position == 0
      assert event.subject_ref == {:user, "zoe"}
      assert event.at == @at
      assert event.operation_id == "backfilled from tables on 2026-03-04 by ExampleRbac.GenesisTest"
    end
  end

  defp ledger do
    {:ok, config} = Turnstile.Config.resolve()
    config.ledger
  end

  defp options do
    {_module, options} = ledger()
    options
  end
end
