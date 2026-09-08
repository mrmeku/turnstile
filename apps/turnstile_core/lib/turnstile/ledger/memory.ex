defmodule Turnstile.Ledger.Memory do
  @moduledoc """
  A ledger in an `Agent`, for tests that need positions without a database.
  It returns what the Ecto ledger returns. Configure it as
  `{Turnstile.Ledger.Memory, agent: pid}` with a pid from `start_link/0`.
  """

  @behaviour Turnstile.Ledger

  alias Turnstile.FactEvent

  @schema NimbleOptions.new!(agent: [type: :pid, required: true, doc: "The agent from `start_link/0`."])

  @typep state :: %{head: non_neg_integer(), events: [FactEvent.t()]}

  @doc "Starts an empty ledger, unnamed."
  @spec start_link() :: Agent.on_start()
  def start_link, do: Agent.start_link(fn -> %{head: 0, events: []} end)

  @impl Turnstile.Ledger
  def options_schema, do: @schema

  @impl Turnstile.Ledger
  def append(options, events) when is_list(options) and is_list(events) do
    {:ok, Agent.get_and_update(agent(options), &stamp(&1, events))}
  end

  @impl Turnstile.Ledger
  def read(options, from, limit) when is_list(options) and is_integer(from) and is_integer(limit) do
    events =
      Agent.get(agent(options), fn %{events: events} ->
        events
        |> Enum.reverse()
        |> Enum.filter(&(&1.position > from))
        |> Enum.take(limit)
      end)

    {:ok, events}
  end

  @impl Turnstile.Ledger
  def head(options) when is_list(options), do: {:ok, Agent.get(agent(options), & &1.head)}

  defp agent(options), do: Keyword.fetch!(options, :agent)

  @spec stamp(state(), [FactEvent.t()]) :: {[FactEvent.t()], state()}
  defp stamp(%{head: head, events: events}, new_events) do
    {stamped, next_head} =
      Enum.map_reduce(new_events, head, fn %FactEvent{} = event, position ->
        {%{event | position: position + 1}, position + 1}
      end)

    {stamped, %{head: next_head, events: Enum.reverse(stamped, events)}}
  end
end
