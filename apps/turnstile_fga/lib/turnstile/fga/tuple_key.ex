defmodule Turnstile.Fga.TupleKey do
  @moduledoc """
  One tuple: a user, a relation, an object, and the condition it carries.

  The first three identify it, which is what `key/1` answers. The condition
  is a value on it, so a tuple whose condition changed is the same key with
  another context, and one `Write` refuses a key that appears in both its
  deletes and its writes (OpenFGA 1.19.0). A change of condition therefore
  takes two calls, the delete first.

  A user, a relation, and an object are the strings the server reads:
  `user:ann`, `reader`, `folder:1`. An object names its type before the
  colon, which is what `object_type/1` answers and what `Read` pages by.
  """

  alias Turnstile.Fga.Condition

  @enforce_keys [:user, :relation, :object]
  defstruct [:user, :relation, :object, condition: nil]

  @typedoc "What identifies a tuple: its user, its relation, and its object."
  @type key :: {String.t(), String.t(), String.t()}

  @type t :: %__MODULE__{
          user: String.t(),
          relation: String.t(),
          object: String.t(),
          condition: Condition.t() | nil
        }

  @doc "What identifies the tuple, without the condition it carries."
  @spec key(t()) :: key()
  def key(%__MODULE__{} = tuple), do: {tuple.user, tuple.relation, tuple.object}

  @doc "The object's type, the part before the colon."
  @spec object_type(t()) :: String.t()
  def object_type(%__MODULE__{object: object}) do
    [type | _id] = String.split(object, ":", parts: 2)
    type
  end

  @doc "The tuple as one line, for the detail of an error and for a drift report."
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = tuple), do: "#{tuple.user} #{tuple.relation} #{tuple.object}"
end
