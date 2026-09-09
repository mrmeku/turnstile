defmodule Turnstile.Fga.Projector.SchedulerTest do
  use ExUnit.Case, async: true

  # The callbacks are called here rather than started. A projector process
  # running in a test would drain against whatever else that test does, so
  # the suite drains by hand, and what is left to prove is what this process
  # resolves and when it drains again.

  alias Turnstile.Error
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Probe
  alias Turnstile.Fga.Projector
  alias Turnstile.Fga.Projector.Scheduler
  alias Turnstile.Fixture.World
  alias Turnstile.Projection.Drain
  alias Turnstile.Test
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "scheduler")
    {:ok, model} = Fake.write_model(agent, store, %{"schema_version" => "1.1"})
    ledger = Probe.ledger()
    handler = :telemetry_test.attach_event_handlers(self(), [Scheduler.event()])
    on_exit(fn -> :telemetry.detach(handler) end)

    :ok =
      Test.with_config(
        adapter: {Fga, endpoint: agent, store_id: store, client: Fake, model_id: model},
        ledger: ledger
      )

    :ok = Binding.override(repo: Sandboxed, model: "priv/conformance/model.fga", mapping: Mapping)

    {:ok, agent: agent, store: store, ledger: ledger}
  end

  test "the event every drain emits is the one an application attaches to" do
    assert Scheduler.event() == [:turnstile, :fga, :drain]
  end

  test "a drain emits how far it reached and what it applied", context do
    _events =
      Probe.append(context.ledger, [Probe.granted("ann", 1, :reader), Probe.clearance("ann", nil, World.cleared())])

    {:ok, {module, projector}} = Fga.projection()

    assert {:ok, %Drain{applied: 2, from: 0, to: 2} = drain} = Scheduler.drain(module, projector)
    assert_received {[:turnstile, :fga, :drain], _ref, measurements, metadata}
    assert measurements == %{applied: 2, from: 0, to: 2}
    assert metadata == %{drain: drain}
  end

  test "a drain that failed emits zeros and the error, so a silent scheduler means nothing broke", context do
    _events = Probe.append(context.ledger, [Probe.granted("ann", 1, :reader)])
    {:ok, {module, projector}} = Fga.projection()

    assert {:error, %Error.Engine{operation: :read} = error} = Scheduler.drain(module, %{projector | store: "store-404"})
    assert_received {[:turnstile, :fga, :drain], _ref, measurements, metadata}
    assert measurements == %{applied: 0, from: 0, to: 0}
    assert metadata == %{error: error}
  end

  test "what it drains with is the projection the adapter declares, on the interval the entry names", context do
    assert {:ok, state, {:continue, :first}} = Scheduler.init([])
    assert state.module == Projector
    assert state.projector.store == context.store
    assert state.interval == 1_000
    assert state.first == 1_000

    assert {:ok, %{interval: 60_000, first: 0}, {:continue, :first}} = Scheduler.init(interval: 60_000, first: 0)
  end

  test "a projection that cannot be resolved stops the process rather than drains nothing forever" do
    Process.delete(Binding)

    assert {:stop, %Error.Invalid{what: :binding}} = Scheduler.init([])
  end

  test "the first drain waits, and every drain schedules the next", context do
    _events = Probe.append(context.ledger, [Probe.granted("ann", 1, :reader)])
    {:ok, state, {:continue, :first}} = Scheduler.init(interval: 60_000, first: 0)

    assert Scheduler.handle_continue(:first, state) == {:noreply, state}
    assert_receive :drain, 500
    assert Scheduler.handle_info(:drain, state) == {:noreply, state}
    assert_received {[:turnstile, :fga, :drain], _ref, %{applied: 1}, %{drain: %Drain{}}}
    refute_received :drain
  end
end
