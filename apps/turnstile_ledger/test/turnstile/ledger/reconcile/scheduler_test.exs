defmodule Turnstile.Ledger.Reconcile.SchedulerTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Reconcile.Scheduler
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population
  alias Turnstile.Projection.Drift
  alias Turnstile.Test

  @repo TestRepos.App
  @exemption Population.exemption()
  @schemas [Account, Folder, Membership]

  setup tags do
    :ok = listen()
    {:ok, context} = Boot.setup(tags)
    [account] = Population.accounts!(@repo, 1)
    {:ok, _record} = Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
    {:ok, Keyword.put(context, :account, account)}
  end

  test "a pass emits the sizes as measurements and the drift as metadata", context do
    assert {:ok, %Drift{} = drift} = Scheduler.pass(pass(context))

    assert_received {[:turnstile, :ledger, :reconcile], _ref, measurements, metadata}
    assert measurements == %{missing: 0, extra: 0, checked_to: drift.checked_to}
    assert metadata == %{drift: drift, clean?: true}
  end

  test "a pass that finds drift says how much of it there is and that the ledger and the tables differ", context do
    Test.with_config([ledger: :none], fn ->
      {:ok, _record} = Facts.bulk_update(Account, [set: [clearance: "patched"]], repo: @repo, turnstile: @exemption)
    end)

    assert {:ok, drift} = Scheduler.pass(pass(context))

    assert_received {[:turnstile, :ledger, :reconcile], _ref, measurements, metadata}
    assert measurements == %{missing: 1, extra: 1, checked_to: drift.checked_to}
    assert metadata == %{drift: drift, clean?: false}
  end

  test "a pass that could not read the ledger emits zeros and the error, so a silent scheduler means nothing broke",
       context do
    Test.with_config(ledger_counter: "missing")

    assert {:error, %Error.Engine{operation: :head} = error} = Scheduler.pass(pass(context))

    assert_received {[:turnstile, :ledger, :reconcile], _ref, measurements, metadata}
    assert measurements == %{missing: 0, extra: 0, checked_to: 0}
    assert metadata == %{error: error}
  end

  test "the event every pass emits is the one an application attaches to" do
    assert Scheduler.event() == [:turnstile, :ledger, :reconcile]
  end

  defp pass(context), do: [ledger: options(context), schemas: @schemas]

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options

  defp listen do
    handler = :telemetry_test.attach_event_handlers(self(), [Scheduler.event()])
    on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end
end
