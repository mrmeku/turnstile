defmodule Turnstile.Ledger.Fold do
  @moduledoc """
  Current state as a fold over fact events, and state at a time as the fold
  stopped there. A fact is keyed by its subject reference, object reference,
  and attribute; an event whose `new` is `nil` erases the fact, any other
  event sets it. A relationship's existence is the fact under the `nil`
  attribute and its value is the row's attributes, so an event that
  changes one attribute of a relationship updates that fact: the value
  itself for a single attribute, one entry of the map for several. The fold
  remembers the last position and time it applied, so a replay can say
  what state it reproduced.
  """

  alias Turnstile.FactEvent

  @enforce_keys [:facts, :position, :at]
  defstruct facts: %{}, position: 0, at: nil

  @typedoc "A fact's key: who, about what, which attribute; `nil` attribute for a relationship's existence."
  @type key :: {Turnstile.Object.ref() | nil, Turnstile.Object.ref() | nil, atom() | nil}

  @type t :: %__MODULE__{facts: %{key() => term()}, position: non_neg_integer(), at: DateTime.t() | nil}

  @doc "The empty fold."
  @spec empty() :: t()
  def empty, do: %__MODULE__{facts: %{}, position: 0, at: nil}

  @doc "Fold every event, in the order given."
  @spec fold([FactEvent.t()]) :: t()
  def fold(events) when is_list(events), do: fold_into(empty(), events)

  @doc "Fold the events onto an existing fold, in the order given."
  @spec fold_into(t(), [FactEvent.t()]) :: t()
  def fold_into(%__MODULE__{} = fold, events) when is_list(events), do: Enum.reduce(events, fold, &apply_event(&2, &1))

  @doc "Fold the events at or before `at`, the state at that time."
  @spec at([FactEvent.t()], DateTime.t()) :: t()
  def at(events, %DateTime{} = at) when is_list(events) do
    events
    |> Enum.filter(&(DateTime.compare(&1.at, at) != :gt))
    |> fold()
  end

  @doc "Fold the events at or below `position`."
  @spec to([FactEvent.t()], non_neg_integer()) :: t()
  def to(events, position) when is_list(events) and is_integer(position) do
    events
    |> Enum.filter(&(is_integer(&1.position) and &1.position <= position))
    |> fold()
  end

  @doc "Apply one event to a fold."
  @spec apply_event(t(), FactEvent.t()) :: t()
  def apply_event(%__MODULE__{} = fold, %FactEvent{} = event) do
    facts = apply_facts(fold.facts, event)

    %__MODULE__{facts: facts, position: event.position || fold.position, at: event.at}
  end

  @doc "The key of an event's fact."
  @spec key(FactEvent.t()) :: key()
  def key(%FactEvent{subject_ref: subject_ref, object_ref: object_ref, attribute: attribute}) do
    {subject_ref, object_ref, attribute}
  end

  defp apply_facts(facts, %FactEvent{attribute: nil} = event), do: apply_value(facts, event)

  defp apply_facts(facts, %FactEvent{kind: :relationship, attribute: attribute} = event) do
    key = {event.subject_ref, event.object_ref, nil}

    case Map.fetch(facts, key) do
      {:ok, %{} = attributes} -> Map.put(facts, key, Map.put(attributes, attribute, event.new))
      _single_or_absent -> Map.put(facts, key, event.new)
    end
  end

  defp apply_facts(facts, event), do: apply_value(facts, event)

  defp apply_value(facts, %FactEvent{new: nil} = event), do: Map.delete(facts, key(event))
  defp apply_value(facts, %FactEvent{new: value} = event), do: Map.put(facts, key(event), value)
end
