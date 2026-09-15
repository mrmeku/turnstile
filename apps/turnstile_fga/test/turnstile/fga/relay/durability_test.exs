defmodule Turnstile.Fga.Relay.DurabilityTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Turnstile.Dev.Sandbox
  alias Turnstile.Fga.Relay.Cursor
  alias Turnstile.Fga.Relay.FlakyJob
  alias Turnstile.Fga.Relay.Infrastructure.Drain
  alias Turnstile.Fga.Relay.Options
  alias Turnstile.Fga.Relay.Pass
  alias Turnstile.Fga.Relay.TestJob
  alias Turnstile.TestRepos.Sandboxed

  # One runner across the whole property, each iteration shipping a
  # population of its own. The cursor carries on from the iteration before,
  # which is what a runner that has been up for a while stands at.
  @runner :durable

  setup tags do
    Sandbox.setup(Sandboxed, tags)
  end

  property "durability: every row reaches the far end once, in position order, however many passes fail" do
    check all(
            rows <- integer(1..6),
            refusals <- list_of(boolean(), min_length: 1, max_length: 8),
            batch <- integer(1..3),
            max_runs: 20
          ) do
      runner = @runner
      population = "durable-#{System.unique_integer([:positive])}"
      :ok = TestJob.write(Sandboxed, population, rows)
      options = options(runner, population, batch)

      Enum.each(refusals, fn refusing? ->
        :ok = FlakyJob.refuse(refusing?)
        _result = Drain.once(options)
      end)

      :ok = FlakyJob.refuse(false)
      :ok = until_empty(options)

      arrived = TestJob.arrived(Sandboxed, population)

      assert length(arrived) == rows
      assert arrived == Enum.sort(arrived)
      assert arrived == Enum.uniq(arrived)
      assert Cursor.position(Sandboxed, runner) == List.last(arrived)
    end
  end

  defp options(runner, population, batch) do
    Options.validate!(
      name: runner,
      repo: Sandboxed,
      job: FlakyJob,
      job_options: [runner: population],
      batch: batch
    )
  end

  defp until_empty(options) do
    case Drain.once(options) do
      {:ok, %Pass{delivered: 0}} -> :ok
      {:ok, %Pass{}} -> until_empty(options)
      {:error, reason} -> flunk("a pass that was not refused failed: #{inspect(reason)}")
    end
  end
end
