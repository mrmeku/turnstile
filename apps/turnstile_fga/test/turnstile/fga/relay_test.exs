defmodule Turnstile.Fga.RelayTest do
  use ExUnit.Case, async: false

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Relay
  alias Turnstile.Fga.Relay.Adapter.Drain
  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.Options
  alias Turnstile.Fga.Relay.Pass
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Sandboxed

  # One pair of names for every test in this module: each runs in a
  # transaction of its own and the processes are stopped with the test.
  @runner :rooted
  @other :rooted_other

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    {:ok, runner: @runner}
  end

  test "the options a runner takes are the ones the package publishes" do
    assert Relay.options_schema() == Options.schema()
  end

  test "a supervisor starts one process per runner, each woken by its own name", %{runner: runner} do
    other = @other
    :ok = attach(runner)
    supervisor = start_supervised!({Relay, name: RootSupervisor, runners: [runner(runner), runner(other)]})

    assert Supervisor.count_children(supervisor).active == 2
    assert is_pid(Process.whereis(runner))
    assert is_pid(Process.whereis(other))

    assert Relay.wake(runner) == :ok
    assert_receive {:pass, %{delivered: 0}}, 5_000
  end

  test "a drain asked for at the root delivers what a runner's tick would", %{runner: runner} do
    :ok = TestJob.write(Sandboxed, Atom.to_string(runner), 3)

    assert {:ok, %Pass{delivered: 3} = pass} = Relay.drain_once(runner(runner))
    assert Cursor.position(Sandboxed, runner) == pass.position
  end

  defp attach(runner) do
    handler = "relay-test-#{System.unique_integer([:positive])}"
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

  defp runner(name) do
    [
      name: name,
      repo: Sandboxed,
      job: TestJob,
      job_options: [runner: Atom.to_string(name)],
      first: 60_000,
      idle: 60_000
    ]
  end
end
