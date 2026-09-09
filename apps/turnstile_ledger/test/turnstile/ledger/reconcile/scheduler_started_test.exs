defmodule Turnstile.Ledger.Reconcile.SchedulerStartedTest do
  use ExUnit.Case, async: false

  alias Turnstile.Config
  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Ledger
  alias Turnstile.Ledger.Reconcile.Scheduler
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Boot
  alias Turnstile.Ledger.TestSupport.Population

  @repo TestRepos.App
  @exemption Population.exemption()
  @schemas [Account, Folder, Membership]

  # A scheduler is a process of its own, so no test's configuration override
  # reaches it: the configuration is booted for the length of this test, as
  # an application boots it. A test that is not async has its sandbox
  # connection shared already, which is how the scheduler sees the rows.
  setup tags do
    handler = :telemetry_test.attach_event_handlers(self(), [Scheduler.event()])
    on_exit(fn -> :telemetry.detach(handler) end)
    {:ok, context} = Boot.setup(tags)
    [_account] = Population.accounts!(@repo, 1)
    {:ok, _record} = Facts.bulk_update(Account, [set: [clearance: "cleared"]], repo: @repo, turnstile: @exemption)
    :ok = boot()
    {:ok, context}
  end

  test "a started scheduler runs its first pass without waiting out the interval", context do
    assert {:ok, pid} = Scheduler.start_link(ledger: options(context), schemas: @schemas, interval: 60_000, first: 0)
    on_exit(fn -> if Process.alive?(pid), do: GenServer.stop(pid) end)

    assert_receive {[:turnstile, :ledger, :reconcile], _ref, measurements, metadata}, 2_000
    assert measurements.missing == 0
    assert measurements.extra == 0
    assert metadata.clean?
  end

  defp boot do
    booted = :persistent_term.get(Config, nil)
    {:ok, config} = Config.resolve()
    _config = Config.boot!(Config.to_keyword(config))
    on_exit(fn -> if booted, do: :persistent_term.put(Config, booted), else: :persistent_term.erase(Config) end)
    :ok
  end

  defp options(%{ledger: {Ledger.Ecto, options}}), do: options
end
