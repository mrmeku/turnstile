defmodule Turnstile.Ledger.Replay do
  @moduledoc """
  State at a time, and the rules in force then. A fold of the ledger stopped
  at a position or a date answers what the facts were; a decision also needed
  the policy version the adapter was running, and the ledger carries those as
  its fourth kind of event, so the two together are what reproduces a
  decision months later. No adapter can do this alone: Elixir modules keep
  nothing, a table keeps only its current row, and a policy engine versions
  its rules without the attributes it was sent.

  A replay reports what it reproduced, `position` and `at`, because a caller
  that asked for a date is entitled to know the last position that date
  covers. Facts before genesis are in the fold at position zero, and a date
  before genesis reproduces nothing, which is the honest answer rather than
  an empty one: `positioned?/1` is false there.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Ledger.Reader]

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Ledger
  alias Turnstile.PolicyVersion

  @enforce_keys [:fold, :policy_version, :position, :at]
  defstruct @enforce_keys

  @typedoc "The fold as of the cut, the policy version in force there, and the cut itself."
  @type t :: %__MODULE__{
          fold: Ledger.Fold.t(),
          policy_version: PolicyVersion.t() | nil,
          position: non_neg_integer(),
          at: DateTime.t() | nil
        }

  @doc """
  Replay to a position: the fold of every event at or below it, and the
  policy version published latest at or below it. `adapter:` narrows the
  policy version to one adapter's, which is what a decision record's
  position and adapter together ask for.
  """
  @spec to({module(), keyword()}, non_neg_integer(), keyword()) :: {:ok, t()} | {:error, Error.Engine.t()}
  def to(ledger, position, options \\ []) when is_integer(position) and is_list(options) do
    with {:ok, events} <- Ledger.Reader.all(ledger) do
      kept = Enum.filter(events, &(is_integer(&1.position) and &1.position <= position))
      {:ok, replay(kept, options, position)}
    end
  end

  @doc "Replay to a date: the fold of every event stamped at or before it, and the policy version in force then."
  @spec at({module(), keyword()}, DateTime.t(), keyword()) :: {:ok, t()} | {:error, Error.Engine.t()}
  def at(ledger, %DateTime{} = at, options \\ []) when is_list(options) do
    with {:ok, events} <- Ledger.Reader.all(ledger) do
      kept = Enum.filter(events, &(DateTime.compare(&1.at, at) != :gt))
      {:ok, %{replay(kept, options, 0) | at: at}}
    end
  end

  @doc "Whether the replay reached a position above genesis, and so reproduces a fact write rather than the backfill."
  @spec positioned?(t()) :: boolean()
  def positioned?(%__MODULE__{position: position}), do: position > 0

  defp replay(events, options, position) do
    %__MODULE__{
      fold: Ledger.Fold.fold(events),
      policy_version: policy_version(events, options[:adapter]),
      position: Enum.reduce(events, position, &max(&1.position || 0, &2)),
      at: last_at(List.last(events))
    }
  end

  defp policy_version(events, adapter) do
    events
    |> Enum.filter(&published?(&1, adapter))
    |> List.last()
    |> version()
  end

  defp published?(%FactEvent{kind: :policy_version, new: %PolicyVersion{}}, nil), do: true

  defp published?(%FactEvent{kind: :policy_version, new: %PolicyVersion{adapter: adapter}}, adapter), do: true

  defp published?(%FactEvent{}, _adapter), do: false

  defp last_at(nil), do: nil
  defp last_at(%FactEvent{at: at}), do: at

  defp version(nil), do: nil
  defp version(%FactEvent{new: %PolicyVersion{} = version}), do: version
end
