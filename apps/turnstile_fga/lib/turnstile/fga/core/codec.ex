defmodule Turnstile.Fga.Core.Codec do
  @moduledoc false
  # A tuple on its way to the server and back. The three fields that
  # identify a tuple are strings, and JSON carries a string as itself, so
  # what the encoding decides is where the condition goes.
  #
  # A delete carries the identifying fields alone and a write carries the
  # condition with them, because the server takes a condition as a value on
  # a tuple rather than as part of what identifies it (OpenFGA 1.19.0). A
  # tuple read back from the store arrives under a `"key"` field, with the
  # condition beside the three where a write put it.
  #
  # The pair that matters is `written/1` and `stored/1`: a tuple the drain
  # writes is the tuple reconcile reads back, or the difference between what
  # the tables ask for and what the store holds is a difference the drain
  # cannot close.

  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.TupleKey

  @doc "What identifies the tuple, which is what a delete carries."
  @spec key(TupleKey.t()) :: map()
  def key(%TupleKey{} = tuple) do
    %{"user" => tuple.user, "relation" => tuple.relation, "object" => tuple.object}
  end

  @doc "The tuple as a write carries it, with the condition it holds."
  @spec written(TupleKey.t()) :: map()
  def written(%TupleKey{condition: nil} = tuple), do: key(tuple)

  def written(%TupleKey{condition: %Condition{} = condition} = tuple) do
    Map.put(key(tuple), "condition", %{"name" => condition.name, "context" => condition.context})
  end

  @doc "The tuple a page of the store holds, read from the key it arrives under."
  @spec stored(map()) :: TupleKey.t()
  def stored(%{"key" => key}) do
    %TupleKey{
      user: key["user"],
      relation: key["relation"],
      object: key["object"],
      condition: condition(Map.get(key, "condition"))
    }
  end

  @doc "The condition a stored tuple carries, or nothing where it carries none."
  @spec condition(map() | nil) :: Condition.t() | nil
  def condition(nil), do: nil
  def condition(%{"name" => name} = json), do: %Condition{name: name, context: Map.get(json, "context") || %{}}
end
