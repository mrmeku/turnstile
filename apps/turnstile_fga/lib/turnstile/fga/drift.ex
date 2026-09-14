defmodule Turnstile.Fga.Drift do
  @moduledoc """
  What a reconcile found: the tuples the tables require and the store lacks,
  the tuples the store holds and no table requires, and the position of the
  last marker the drain had delivered when the comparison was taken.

  A drift that is clean says the store and the tables agree. A drift that is
  not says where they differ, tuple by tuple, so an operator reads what to
  repair rather than a count. Markers written while the comparison ran are
  above `checked_to`, which is what says how current a clean answer is.
  """

  alias Turnstile.Fga.TupleKey

  @enforce_keys [:missing, :extra, :checked_to]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          missing: [TupleKey.t()],
          extra: [TupleKey.t()],
          checked_to: non_neg_integer()
        }

  @doc "Whether nothing differs."
  @spec clean?(t()) :: boolean()
  def clean?(%__MODULE__{missing: [], extra: []}), do: true
  def clean?(%__MODULE__{}), do: false
end
