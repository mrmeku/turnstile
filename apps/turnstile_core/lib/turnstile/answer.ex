defmodule Turnstile.Answer do
  @moduledoc """
  What an adapter answers for one subject, operation, and object, before the
  port stamps it into a `Turnstile.Decision`: the verdict, the reason, the
  policy version in force, and the ledger position the adapter's state had
  applied, `nil` where the adapter reads live state or there is no ledger.
  """

  @enforce_keys [:verdict, :reason, :policy_version, :applied_position]
  defstruct [:verdict, :reason, :policy_version, :applied_position]

  @type verdict :: :allow | :deny

  @type t :: %__MODULE__{
          verdict: verdict(),
          reason: Turnstile.Reason.t(),
          policy_version: Turnstile.PolicyVersion.ref(),
          applied_position: non_neg_integer() | nil
        }
end
