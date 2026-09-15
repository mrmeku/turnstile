defmodule Turnstile.Fga.Relay.ContentionTest do
  use ExUnit.Case, async: false

  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.Infrastructure.Drain
  alias Turnstile.Fga.Relay.Infrastructure.Lock
  alias Turnstile.Fga.Relay.Options
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Committed

  @moduletag :committed

  # Two connections is what contention needs, so this module runs on the
  # committed tier rather than in a sandbox transaction.
  @runner :contended

  test "a second connection asking for a lock another holds is told no, and is told yes once it is released" do
    holder = hold()
    assert_receive {:held, true}, 10_000

    assert Committed.transaction(fn -> Lock.taken?(Committed, @runner) end) == {:ok, false}

    assert release(holder) == {:ok, :ok}
    assert Committed.transaction(fn -> Lock.taken?(Committed, @runner) end) == {:ok, true}
  end

  test "a pass that finds another node delivering steps aside, reporting the cursor and delivering nothing" do
    population = "aside-#{System.unique_integer([:positive])}"
    :ok = TestJob.write(Committed, population, 2)
    options = Options.validate!(name: @runner, repo: Committed, job: TestJob, job_options: [runner: population])
    stood_at = Cursor.position(Committed, @runner)

    holder = hold()
    assert_receive {:held, true}, 10_000

    assert {:ok, aside} = Drain.once(options)
    refute aside.held?
    assert aside.delivered == 0
    assert aside.position == stood_at
    assert TestJob.arrived(Committed, population) == []

    assert release(holder) == {:ok, :ok}
    assert {:ok, delivered} = Drain.once(options)
    assert delivered.held?
    assert delivered.delivered == 2
  end

  # Holds the runner's lock on a connection of its own until it is released.
  defp hold do
    parent = self()

    Task.async(fn ->
      Committed.transaction(
        fn ->
          send(parent, {:held, Lock.taken?(Committed, @runner)})

          receive do
            :release -> :ok
          after
            10_000 -> :ok
          end
        end,
        timeout: 30_000
      )
    end)
  end

  defp release(holder) do
    send(holder.pid, :release)

    Task.await(holder, 10_000)
  end
end
