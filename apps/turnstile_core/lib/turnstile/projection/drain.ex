defmodule Turnstile.Projection.Drain do
  @moduledoc "What one `drain_once/1` did: the checkpoint before, the checkpoint after, and how many events it applied."

  @enforce_keys [:from, :to, :applied]
  defstruct @enforce_keys

  @type t :: %__MODULE__{from: non_neg_integer(), to: non_neg_integer(), applied: non_neg_integer()}
end
