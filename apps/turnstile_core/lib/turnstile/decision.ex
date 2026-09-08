defmodule Turnstile.Decision do
  @moduledoc "What the port said, when, from what state, under which rules."

  alias Turnstile.Edge
  alias Turnstile.Error
  alias Turnstile.Reason
  alias Turnstile.Subject

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
    :head_position,
    :applied_position,
    :operation_id,
    :at
  ]
  defstruct @enforce_keys

  @typedoc "`:scoped` is the verdict of a `scope` decision, whose rule narrows rather than allows."
  @type verdict :: :allow | :deny | :scoped

  @typedoc """
  Two positions, not one: the head at decision time and the position the
  adapter's state had applied, equal unless the adapter projects, both `nil`
  in ledger mode none.
  """
  @type t :: %__MODULE__{
          id: Turnstile.Id.t(),
          subject: Subject.t(),
          object: Turnstile.Object.ref(),
          operation: atom(),
          verdict: verdict(),
          reason: Reason.t(),
          adapter: module(),
          policy_version: Turnstile.PolicyVersion.ref() | nil,
          head_position: non_neg_integer() | nil,
          applied_position: non_neg_integer() | nil,
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
      subject: Subject.to_map(decision.subject),
      object: Edge.ref_out(decision.object),
      operation: Atom.to_string(decision.operation),
      verdict: Atom.to_string(decision.verdict),
      reason: Reason.to_map(decision.reason),
      adapter: Edge.module_out(decision.adapter),
      policy_version: decision.policy_version,
      head_position: decision.head_position,
      applied_position: decision.applied_position,
      operation_id: decision.operation_id,
      at: Edge.time_out(decision.at)
    }
  end

  @doc "A map back to the decision."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def from_map(map) when is_map(map) do
    with {:ok, fields} <- Edge.convert(map, spec(), :decision) do
      {:ok, struct!(__MODULE__, fields)}
    end
  end

  defp spec do
    [
      id: :string,
      subject: {:struct, Subject},
      object: :ref,
      operation: :atom,
      verdict: {:in, @verdicts},
      reason: {:struct, Reason},
      adapter: :module,
      policy_version: {:string, :nil_ok},
      head_position: {:integer, :nil_ok},
      applied_position: {:integer, :nil_ok},
      operation_id: :string,
      at: :time
    ]
  end
end
