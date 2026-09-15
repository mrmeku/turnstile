defmodule Turnstile.Fga.Relay.DrainTest do
  use ExUnit.Case, async: true

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.FlakyJob
  alias Turnstile.Fga.Relay.Infrastructure.Drain
  alias Turnstile.Fga.Relay.Job
  alias Turnstile.Fga.Relay.Options
  alias Turnstile.Fga.Relay.Pass
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Sandboxed

  @moment ~U[2026-01-01 00:00:00Z]

  defmodule Unreadable do
    @moduledoc false
    @behaviour Job

    @impl Job
    def options_schema, do: NimbleOptions.new!([])

    @impl Job
    def read(_repo, _options, _from, _limit), do: {:error, :unreadable}

    @impl Job
    def deliver(_repo, _options, _entries), do: :ok
  end

  defmodule Unreachable do
    @moduledoc false

    @spec transaction((-> term()), keyword()) :: no_return()
    def transaction(_fun, _options), do: raise(RuntimeError, "connection refused")
  end

  # One name for every test in this module: each runs in a transaction of
  # its own, so no test sees another's rows, cursor, or lock.
  @runner :draining

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    {:ok, runner: @runner}
  end

  test "a pass with nothing to deliver holds the lock and leaves the cursor where it was", %{runner: runner} do
    assert {:ok, %Pass{} = pass} = Drain.once(options(runner))

    assert pass.name == runner
    assert pass.held?
    assert pass.delivered == 0
    assert pass.position == 0
    refute pass.more?
    assert Cursor.position(Sandboxed, runner) == 0
  end

  test "a pass delivers the batch and advances the cursor to its last position", %{runner: runner} do
    :ok = TestJob.write(Sandboxed, Atom.to_string(runner), 3)

    assert {:ok, %Pass{delivered: 3} = pass} = Drain.once(options(runner))
    assert length(TestJob.arrived(Sandboxed, Atom.to_string(runner))) == 3
    assert Cursor.position(Sandboxed, runner) == pass.position
    refute pass.more?
  end

  test "a batch that filled says the rows behind it are already waiting", %{runner: runner} do
    :ok = TestJob.write(Sandboxed, Atom.to_string(runner), 4)

    assert {:ok, %Pass{delivered: 2, more?: true}} = Drain.once(options(runner, batch: 2))
    assert {:ok, %Pass{delivered: 2, more?: true}} = Drain.once(options(runner, batch: 2))
    assert {:ok, %Pass{delivered: 0, more?: false}} = Drain.once(options(runner, batch: 2))
  end

  test "a delivery that fails leaves the cursor where it was and nothing at the far end", %{runner: runner} do
    :ok = TestJob.write(Sandboxed, Atom.to_string(runner), 3)
    :ok = FlakyJob.refuse(true)

    assert Drain.once(options(runner, job: FlakyJob)) == {:error, :refused}
    assert TestJob.arrived(Sandboxed, Atom.to_string(runner)) == []
    assert Cursor.position(Sandboxed, runner) == 0
  end

  test "a read that fails is the pass's failure, carrying the job's own term", %{runner: runner} do
    assert Drain.once(options(runner, job: Unreadable, job_options: [])) == {:error, :unreadable}
  end

  test "a repo that cannot be reached is a pass that failed, not a process that died", %{runner: runner} do
    assert {:error, %RuntimeError{}} = Drain.once(options(runner, repo: Unreachable))
  end

  test "the moment on a pass comes from the clock the options carry", %{runner: runner} do
    assert {:ok, %Pass{at: @moment}} = Drain.once(options(runner, clock: fn -> @moment end))
  end

  test "a pass that delivered and a pass that failed each emit one event", %{runner: runner} do
    :ok = TestJob.write(Sandboxed, Atom.to_string(runner), 2)
    :ok = attach(runner)

    {:ok, _delivered} = Drain.once(options(runner))
    assert_received {:pass, %{delivered: 2}, %{name: ^runner, pass: %Pass{}}}

    {:error, :unreadable} = Drain.once(options(runner, job: Unreadable, job_options: []))
    assert_received {:pass, %{delivered: 0}, %{name: ^runner, error: :unreadable}}
  end

  defp options(runner, overrides \\ []) do
    [name: runner, repo: Sandboxed, job: TestJob, job_options: [runner: Atom.to_string(runner)]]
    |> Keyword.merge(overrides)
    |> Options.validate!()
  end

  defp attach(runner) do
    handler = "drain-test-#{System.unique_integer([:positive])}"
    parent = self()

    :ok =
      :telemetry.attach(
        handler,
        Drain.event(),
        fn _event, measurements, metadata, {pid, watched} ->
          if metadata.name == watched, do: send(pid, {:pass, measurements, metadata})
        end,
        {parent, runner}
      )

    on_exit(fn -> :telemetry.detach(handler) end)
  end
end
