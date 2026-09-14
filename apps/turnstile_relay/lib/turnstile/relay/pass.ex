defmodule Turnstile.Relay.Pass do
  @moduledoc """
  What one pass did: whether it held the lock, how many entries it
  delivered, where its cursor stands, whether the batch was full, and the
  moment it finished, read from the clock the runner was configured with.

  `more?` is what the runner reads to decide whether to pass again at once:
  a full batch means the rows that follow it are already waiting.
  """

  @enforce_keys [:name, :held?, :delivered, :position, :more?, :at]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          name: atom(),
          held?: boolean(),
          delivered: non_neg_integer(),
          position: non_neg_integer(),
          more?: boolean(),
          at: DateTime.t()
        }
end
