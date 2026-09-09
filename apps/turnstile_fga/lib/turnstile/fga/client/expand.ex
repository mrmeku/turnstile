defmodule Turnstile.Fga.Client.Expand do
  @moduledoc """
  The tree behind one relation on one object: who holds it directly, and
  which relations it is computed from. It answers no question about a
  single user, which is why it is the path explanation rather than the
  decision.
  """

  @enforce_keys [:relation, :object]
  defstruct [:relation, :object, :model]

  @type t :: %__MODULE__{relation: String.t(), object: String.t(), model: String.t() | nil}
end
