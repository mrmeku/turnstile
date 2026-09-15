defmodule Turnstile.Decision do
  @moduledoc "What the port said, when, from what state, under which rules."

  alias Turnstile.Answer

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
end
