defmodule Turnstile.Fga.Client.Write do
  @moduledoc """
  The tuples one call deletes and the tuples it writes. The server applies
  them together or not at all, counts them against one limit, and refuses a
  key that appears on both sides, so a caller states both lists and keeps
  each call under `Turnstile.Fga.Client.max_tuples_per_write/0`.
  """

  alias Turnstile.Fga.TupleKey

  @enforce_keys [:deletes, :writes]
  defstruct @enforce_keys

  @type t :: %__MODULE__{deletes: [TupleKey.t()], writes: [TupleKey.t()]}
end
