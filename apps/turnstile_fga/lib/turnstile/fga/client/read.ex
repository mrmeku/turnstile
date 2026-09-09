defmodule Turnstile.Fga.Client.Read do
  @moduledoc """
  Tuples as they are stored, which no decision consults and both the drain
  and reconcile do. The object type is required, because that is the unit
  the store pages by; an object id narrows it to one object, and a relation
  or a user narrows it further.

  `limit` is how many tuples one page holds and `continuation` is what the
  previous page answered with, so a caller reads to the end by asking again
  until the continuation is nothing.
  """

  @enforce_keys [:object_type]
  defstruct [:object_type, :object_id, :relation, :user, :continuation, limit: 100]

  @type t :: %__MODULE__{
          object_type: String.t(),
          object_id: String.t() | nil,
          relation: String.t() | nil,
          user: String.t() | nil,
          continuation: String.t() | nil,
          limit: pos_integer()
        }
end
