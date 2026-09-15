defmodule Turnstile.Fga.Relay.FlakyJob do
  @moduledoc """
  The test job with a delivery that reaches the far end and then fails, when
  the process running the pass says so. A pass runs in the process that
  called `Turnstile.Fga.Relay.drain_once/1`, so a test says `refuse/1` before
  each pass and reads afterwards whether the rows the delivery wrote stayed.

  Failing after the write rather than before it is the point: what it proves
  is that a pass that does not commit leaves nothing behind, not that a
  delivery which never ran wrote nothing.
  """

  @behaviour Turnstile.Fga.Relay.Job

  use Boundary, top_level?: true, deps: [NimbleOptions, Turnstile.Fga.Relay, Turnstile.Fga.Relay.TestJob]

  alias Turnstile.Fga.Relay.Entry
  alias Turnstile.Fga.Relay.Job
  alias Turnstile.Fga.Relay.TestJob

  @key __MODULE__

  @doc "Say whether the next delivery in this process fails after writing."
  @spec refuse(boolean()) :: :ok
  def refuse(refusing?) when is_boolean(refusing?) do
    _previous = Process.put(@key, refusing?)

    :ok
  end

  @impl Job
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: TestJob.options_schema()

  @impl Job
  @spec read(module(), keyword(), non_neg_integer(), pos_integer()) :: {:ok, [Entry.t()]}
  def read(repo, options, from, limit), do: TestJob.read(repo, options, from, limit)

  @impl Job
  @spec deliver(module(), keyword(), [Entry.t()]) :: :ok | {:error, :refused}
  def deliver(repo, options, entries) do
    :ok = TestJob.deliver(repo, options, entries)

    if Process.get(@key, false), do: {:error, :refused}, else: :ok
  end
end
