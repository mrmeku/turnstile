defmodule Turnstile.Fga.Relay.RunnerTest do
  use ExUnit.Case, async: false

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Relay
  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.Infrastructure.Drain
  alias Turnstile.Fga.Relay.Infrastructure.Runner
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Sandboxed

  # One name for every test in this module: each runs in a transaction of
  # its own and the process started under the name is stopped with the test.
  @runner :running

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = attach(@runner)
    {:ok, runner: @runner}
  end

  test "a runner passes on its first tick and advances the cursor", %{runner: runner} do
    :ok = TestJob.write(Sandboxed, Atom.to_string(runner), 2)
    _pid = start!(runner, first: 10)

    assert_receive {:pass, %{delivered: 2, position: position}}, 5_000
    assert Cursor.position(Sandboxed, runner) == position
  end

  test "a wake-up brings the next pass forward from a tick that is far off", %{runner: runner} do
    pid = start!(runner, first: 60_000, idle: 60_000)
    refute_receive {:pass, _measurements}, 200

    assert Relay.wake(pid) == :ok
    assert_receive {:pass, %{delivered: 0}}, 5_000
  end

  test "a runner registered under its name is woken by that name", %{runner: runner} do
    _pid = start!(runner, first: 60_000, idle: 60_000, register: true)

    assert is_pid(Process.whereis(runner))
    assert Relay.wake(runner) == :ok
    assert_receive {:pass, %{delivered: 0}}, 5_000
  end

  test "a wake-up that arrives while a pass is already pending is dropped" do
    state = %Runner{options: [], failures: 0, timer: nil}

    assert Runner.handle_cast(:wake, state) == {:noreply, state}
  end

  test "each runner is its own child of a supervisor, named by its runner", %{runner: runner} do
    assert Runner.child_spec(name: runner) == %{
             id: {Runner, runner},
             start: {Runner, :start_link, [[name: runner]]}
           }
  end

  defp start!(runner, overrides) do
    options =
      Keyword.merge(
        [name: runner, repo: Sandboxed, job: TestJob, job_options: [runner: Atom.to_string(runner)], register: false],
        overrides
      )

    start_supervised!(%{id: {Runner, runner}, start: {Runner, :start_link, [options]}})
  end

  defp attach(runner) do
    handler = "runner-test-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        Drain.event(),
        fn _event, measurements, %{name: name}, {pid, watched} ->
          if name == watched, do: send(pid, {:pass, measurements})
        end,
        {parent, runner}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end
end
