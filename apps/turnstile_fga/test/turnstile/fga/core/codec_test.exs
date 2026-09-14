defmodule Turnstile.Fga.CodecTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.Core.Codec
  alias Turnstile.Fga.TupleKey

  property "a tuple the drain writes is the tuple reconcile reads back" do
    check all(tuple <- tuple_key()) do
      assert Codec.stored(%{"key" => crossed(Codec.written(tuple))}) == tuple
    end
  end

  property "a delete carries what identifies a tuple, and a write carries the condition with it" do
    check all(tuple <- tuple_key()) do
      identifying = Codec.key(tuple)

      assert Enum.sort(Map.keys(identifying)) == ["object", "relation", "user"]
      assert Map.take(Codec.written(tuple), Map.keys(identifying)) == identifying
      assert Map.has_key?(Codec.written(tuple), "condition") == (tuple.condition != nil)
    end
  end

  property "two tuples the store holds under one key differ only where their conditions do" do
    check all(tuple <- tuple_key(), condition <- condition()) do
      other = %{tuple | condition: condition}

      assert TupleKey.key(Codec.stored(%{"key" => crossed(Codec.written(other))})) == TupleKey.key(tuple)
    end
  end

  test "a stored tuple whose condition carries no context reads back as one carrying an empty one" do
    key = %{"user" => "user:ann", "relation" => "reader", "object" => "folder:1", "condition" => %{"name" => "while"}}

    assert Codec.stored(%{"key" => key}).condition == %Condition{name: "while", context: %{}}
  end

  # The tuple as JSON carries it to the server and back, which is the only
  # form the store ever holds.
  defp crossed(written), do: JSON.decode!(JSON.encode!(written))

  defp tuple_key do
    gen all(
          user <- identifier(),
          relation <- identifier(),
          object <- identifier(),
          condition <- one_of([constant(nil), condition()])
        ) do
      %TupleKey{user: user, relation: relation, object: object, condition: condition}
    end
  end

  defp condition do
    gen all(name <- identifier(), context <- map_of(identifier(), parameter(), max_length: 4)) do
      %Condition{name: name, context: context}
    end
  end

  defp identifier, do: string(:printable, min_length: 1, max_length: 12)

  defp parameter do
    one_of([identifier(), integer(), boolean(), constant(nil), list_of(identifier(), max_length: 3)])
  end
end
