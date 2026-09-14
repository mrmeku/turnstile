defmodule Turnstile.Relay.Entry do
  @moduledoc """
  One row on its way out: the position that orders it against every other
  row of the same runner, and the payload the job read from its own table.
  What a payload holds is the job's, and the relay reads nothing in it.

  Positions rise and are unique within a runner. A `bigserial` column is the
  usual source of one, and any column a job can read in ascending order
  serves.
  """

  @enforce_keys [:position, :payload]
  defstruct @enforce_keys

  @type t :: %__MODULE__{position: pos_integer(), payload: term()}
end
