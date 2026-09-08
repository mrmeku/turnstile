defmodule Turnstile.Decision do
  @moduledoc "What the port said, when, from what state, under which rules."

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
          subject: Turnstile.Subject.t(),
          object: Turnstile.Object.ref(),
          operation: atom(),
          verdict: verdict(),
          reason: Turnstile.Reason.t(),
          adapter: module(),
          policy_version: Turnstile.PolicyVersion.ref(),
          head_position: non_neg_integer() | nil,
          applied_position: non_neg_integer() | nil,
          operation_id: Turnstile.Id.t(),
          at: DateTime.t()
        }
end
