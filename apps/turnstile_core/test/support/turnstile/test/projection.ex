defmodule Turnstile.Test.Projection do
  @moduledoc """
  A projection over a ledger held in an `Agent`, for the three projection
  cases of Tier 1 without an engine: `drain_once/1` folds the next batch of
  events into the agent, `reconcile/1` compares the agent with the fold to
  the checkpoint, `rebuild/1` folds into a fresh agent, `disturb/1` writes a
  fact into the agent behind the projector's back, and `interrupt/1`
  returns a configuration whose next drain applies one event and fails
  before advancing.
  """

  @behaviour Turnstile.Conformance.Projected
  @behaviour Turnstile.Projection

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Conformance]

  alias Turnstile.Conformance.Projected
  alias Turnstile.Error
  alias Turnstile.Ledger.Fold
  alias Turnstile.Projection.Drain
  alias Turnstile.Projection.Drift

  @enforce_keys [:agent, :ledger]
  defstruct [:agent, :ledger, batch: 100, interrupt_after: nil]

  @type t :: %__MODULE__{
          agent: pid(),
          ledger: {module(), keyword()},
          batch: pos_integer(),
          interrupt_after: pos_integer() | nil
        }

  @doc "Starts an empty projection state, unnamed."
  @spec start_link() :: Agent.on_start()
  def start_link, do: Agent.start_link(fn -> Fold.empty() end)

  @doc "The facts the state holds."
  @spec facts(t()) :: %{Fold.key() => term()}
  def facts(%__MODULE__{agent: agent}), do: Agent.get(agent, & &1.facts)

  @impl Turnstile.Projection
  def checkpoint(%__MODULE__{agent: agent}), do: {:ok, Agent.get(agent, & &1.position)}

  @impl Turnstile.Projection
  def drain_once(%__MODULE__{ledger: {module, options}} = projection) do
    {:ok, from} = checkpoint(projection)

    with {:ok, events} <- module.read(options, from, projection.batch) do
      apply_batch(projection, from, events)
    end
  end

  @impl Turnstile.Projection
  def rebuild(%__MODULE__{} = projection) do
    with {:ok, events} <- all_events(projection) do
      {:ok, agent} = Agent.start_link(fn -> Fold.fold(events) end)
      {:ok, inspect(agent)}
    end
  end

  @impl Turnstile.Projection
  def reconcile(%__MODULE__{agent: agent} = projection) do
    with {:ok, events} <- all_events(projection) do
      %Fold{facts: state, position: checkpoint} = Agent.get(agent, & &1)
      expected = Fold.to(events, checkpoint).facts
      {:ok, drift(expected, state, checkpoint)}
    end
  end

  @impl Projected
  def disturb(%__MODULE__{agent: agent}) do
    Agent.update(agent, fn fold -> %{fold | facts: Map.put(fold.facts, {{:user, "nobody"}, {:nowhere, 0}, nil}, true)} end)
  end

  @impl Projected
  def interrupt(%__MODULE__{} = projection), do: %{projection | interrupt_after: 1}

  defp drift(expected, state, checkpoint) do
    missing = for {key, value} <- expected, Map.get(state, key) != value, do: {key, value}
    extra = for {key, value} <- state, not Map.has_key?(expected, key), do: {key, value}
    %Drift{missing: Enum.sort(missing), extra: Enum.sort(extra), checked_to: checkpoint}
  end

  defp apply_batch(%__MODULE__{interrupt_after: nil, agent: agent}, from, events) do
    fold =
      Agent.get_and_update(agent, fn fold ->
        folded = Fold.fold_into(fold, events)
        {folded, folded}
      end)

    {:ok, %Drain{from: from, to: fold.position, applied: length(events)}}
  end

  defp apply_batch(%__MODULE__{interrupt_after: count, agent: agent}, _from, events) do
    {applied, _rest} = Enum.split(events, count)

    Agent.update(agent, fn fold ->
      %{fold | facts: Fold.fold_into(fold, applied).facts}
    end)

    {:error,
     %Error.Engine{
       adapter: __MODULE__,
       operation: :drain_once,
       detail: "interrupted after #{length(applied)} of #{length(events)} events, before the checkpoint advanced"
     }}
  end

  defp all_events(%__MODULE__{ledger: {module, options}}) do
    with {:ok, head} <- module.head(options) do
      module.read(options, 0, max(head, 1))
    end
  end
end
