defmodule Turnstile.Fga.Client.ListObjects do
  @moduledoc """
  Every object of one type the user holds one relation on. The answer is a
  list of objects, which is what makes a scope one query on the
  application's side: the ids go into the rule the port hands back.

  The server caps how many objects it will answer with, so a caller that
  cares whether the list is whole compares its length against the cap it
  declared.
  """

  alias Turnstile.Fga.Consistency

  @enforce_keys [:user, :relation, :type]
  defstruct [:user, :relation, :type, :model, context: %{}, consistency: :unspecified]

  @type t :: %__MODULE__{
          user: String.t(),
          relation: String.t(),
          type: String.t(),
          model: String.t() | nil,
          context: %{String.t() => term()},
          consistency: Consistency.t()
        }
end
