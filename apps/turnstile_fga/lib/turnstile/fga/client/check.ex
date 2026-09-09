defmodule Turnstile.Fga.Client.Check do
  @moduledoc """
  One question: does this tuple hold. The tuple key names the user, the
  relation, and the object asked about; the context is what the model's
  conditions are evaluated against, which is where the environment of a
  request goes; the model id pins which model answers, so a decision is
  taken under a version rather than under whatever is current.
  """

  alias Turnstile.Fga.Consistency
  alias Turnstile.Fga.TupleKey

  @enforce_keys [:tuple_key]
  defstruct [:tuple_key, :model, context: %{}, consistency: :unspecified]

  @type t :: %__MODULE__{
          tuple_key: TupleKey.t(),
          model: String.t() | nil,
          context: %{String.t() => term()},
          consistency: Consistency.t()
        }
end
