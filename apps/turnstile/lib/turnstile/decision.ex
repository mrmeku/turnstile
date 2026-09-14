defmodule Turnstile.Decision do
  @moduledoc "What the port said, when, from what state, under which rules."

  alias Turnstile.Answer
  alias Turnstile.Edge
  alias Turnstile.Error

  @verdicts [:allow, :deny, :scoped]

  @enforce_keys [
    :id,
    :subject,
    :object,
    :operation,
    :verdict,
    :reason,
    :adapter,
    :policy_version,
    :operation_id,
    :at
  ]
  defstruct @enforce_keys

  @typedoc "`:scoped` is the verdict of a `scope` decision, whose rule narrows rather than allows."
  @type verdict :: :allow | :deny | :scoped

  @typedoc "`policy_version` is `nil` where the adapter names no version for the answer."
  @type t :: %__MODULE__{
          id: Turnstile.Id.t(),
          subject: Turnstile.subject(),
          object: Turnstile.object(),
          operation: atom(),
          verdict: verdict(),
          reason: Answer.reason(),
          adapter: module(),
          policy_version: Turnstile.PolicyVersion.ref() | nil,
          operation_id: Turnstile.Id.t(),
          at: DateTime.t()
        }

  @doc "The three verdicts."
  @spec verdicts() :: [verdict()]
  def verdicts, do: @verdicts

  @doc "The decision as a map of plain values, the shape a telemetry record carries."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = decision) do
    %{
      id: decision.id,
      subject: Edge.ref_out(decision.subject),
      object: Edge.ref_out(decision.object),
      operation: Atom.to_string(decision.operation),
      verdict: Atom.to_string(decision.verdict),
      reason: Atom.to_string(decision.reason),
      adapter: Edge.module_out(decision.adapter),
      policy_version: decision.policy_version,
      operation_id: decision.operation_id,
      at: Edge.time_out(decision.at)
    }
  end

  @doc "A map back to the decision."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.t()}
  def from_map(map) when is_map(map) do
    with {:ok, fields} <- Edge.convert(map, spec(), :decision) do
      {:ok, struct!(__MODULE__, fields)}
    end
  end

  defp spec do
    [
      id: :string,
      subject: :ref,
      object: :ref,
      operation: :atom,
      verdict: {:in, @verdicts},
      reason: {:in, Answer.reasons()},
      adapter: :module,
      policy_version: {:string, :nil_ok},
      operation_id: :string,
      at: :time
    ]
  end
end
