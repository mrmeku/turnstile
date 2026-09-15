defmodule Turnstile.Fga.Relay.JobTest do
  # What a runner relies on of a job, held against the job this package
  # proves itself over: a read answers entries above the position it was
  # given, in position order, and no more of them than the limit; positions
  # rise and are unique, so a cursor holding the last position of a batch
  # holds every position in it; and a batch already delivered may be
  # delivered again, since a pass that does not commit is read again.
  use ExUnit.Case, async: true

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Relay
  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Sandboxed

  @written 5

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = TestJob.write(Sandboxed, @written)
    :ok
  end

  test "the options the job is used with are the options its own schema accepts" do
    assert {:ok, _validated} = NimbleOptions.validate([], TestJob.options_schema())
  end

  test "a read answers entries above the position given, in position order, no more than the limit" do
    {:ok, batch} = read(0, 3)
    positions = Enum.map(batch, & &1.position)
    {:ok, rest} = read(List.last(positions), 3)

    assert length(batch) == 3
    assert positions == Enum.sort(positions)
    assert Enum.all?(rest, &(&1.position > List.last(positions)))
  end

  test "positions rise and are unique, so the last of a batch stands for every one in it" do
    {:ok, entries} = read(0, 100)
    positions = Enum.map(entries, & &1.position)

    assert length(positions) >= @written
    assert positions == Enum.sort(positions)
    assert positions == Enum.uniq(positions)
  end

  test "a read above the last position answers nothing" do
    {:ok, entries} = read(0, 100)

    assert read(List.last(entries).position, 100) == {:ok, []}
  end

  test "a batch already delivered may be delivered again, since a pass that did not commit is read again" do
    {:ok, entries} = read(0, 100)

    assert TestJob.deliver(Sandboxed, options(), entries) == :ok
    assert TestJob.deliver(Sandboxed, options(), entries) == :ok
  end

  test "a pass delivers the entries above the cursor and leaves the cursor at the last of them" do
    options = [name: TestJob, repo: Sandboxed, job: TestJob, job_options: [], batch: 100]
    {:ok, pass} = Relay.drain_once(options)
    {:ok, again} = Relay.drain_once(options)

    assert pass.held?
    assert pass.delivered >= @written
    assert pass.position == Cursor.position(Sandboxed, TestJob)
    assert again.delivered == 0
    assert again.position == pass.position
  end

  # The job's own options as a runner would hand them, with the defaults
  # filled in as `Turnstile.Fga.Relay.Options` fills them in there.
  defp options, do: NimbleOptions.validate!([], TestJob.options_schema())

  defp read(from, limit), do: TestJob.read(Sandboxed, options(), from, limit)
end
