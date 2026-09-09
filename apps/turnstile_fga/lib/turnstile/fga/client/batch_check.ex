defmodule Turnstile.Fga.Client.BatchCheck do
  @moduledoc """
  Many questions in one call. Each is a correlation id of the caller's
  choosing and the tuple key it asks about, and the answer comes back keyed
  by those ids, so a caller pairs answers with what it asked without
  relying on order.

  The context, the model id, and the consistency are the call's, not the
  item's: one batch is one request, taken under one model, against one
  environment.
  """

  alias Turnstile.Fga.Consistency
  alias Turnstile.Fga.TupleKey

  @enforce_keys [:checks]
  defstruct [:checks, :model, context: %{}, consistency: :unspecified]

  @typedoc "A correlation id and the tuple it asks about."
  @type item :: {String.t(), TupleKey.t()}

  @type t :: %__MODULE__{
          checks: [item()],
          model: String.t() | nil,
          context: %{String.t() => term()},
          consistency: Consistency.t()
        }
end
