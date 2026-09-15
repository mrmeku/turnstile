defmodule Turnstile.Fga.DrainTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.Domain.Drain
  alias Turnstile.Fga.TupleKey

  property "the calls of a difference leave the store holding what the object requires" do
    check all({required, present} <- states(), batch <- integer(1..8)) do
      {deletes, writes} = Drain.difference(required, present)

      assert applied(Drain.calls(deletes, writes, batch), present) == Enum.sort(Enum.uniq(required))
    end
  end

  property "a store that already holds what an object requires is told nothing" do
    check all({required, _present} <- states(), batch <- integer(1..8)) do
      {deletes, writes} = Drain.difference(required, required)

      assert {deletes, writes} == {[], []}
      assert Drain.calls(deletes, writes, batch) == []
    end
  end

  property "no call carries a key on both of its sides, and the delete of a key comes before its write" do
    check all({required, present} <- states(), batch <- integer(1..8)) do
      {deletes, writes} = Drain.difference(required, present)
      calls = Drain.calls(deletes, writes, batch)

      for %Write{} = call <- calls do
        assert MapSet.disjoint?(keys(call.deletes), keys(call.writes))
      end

      for key <- MapSet.intersection(keys(deletes), keys(writes)) do
        assert at(calls, key, & &1.deletes) < at(calls, key, & &1.writes)
      end
    end
  end

  property "every call carries at most the changes one call may carry" do
    check all({required, present} <- states(), batch <- integer(1..8)) do
      {deletes, writes} = Drain.difference(required, present)

      for %Write{} = call <- Drain.calls(deletes, writes, batch) do
        assert (length(call.deletes) + length(call.writes)) in 1..batch
      end
    end
  end

  property "a tuple whose condition changed is one key deleted and written again" do
    check all(tuple <- tuple_key(), clearance <- member_of(~w(low high))) do
      was = %{tuple | condition: %Condition{name: "while", context: %{"clearance" => clearance}}}
      now = %{was | condition: %Condition{name: "while", context: %{"clearance" => clearance <> " enough"}}}
      {deletes, writes} = Drain.difference([now], [was])

      assert {deletes, writes} == {[was], [now]}
      assert Drain.calls(deletes, writes, 8) == [%Write{deletes: [was], writes: []}, %Write{deletes: [], writes: [now]}]
    end
  end

  # The store as the calls leave it: a delete takes a key away and a write
  # puts one back, whatever the key held before.
  defp applied(calls, present) do
    held = Map.new(present, &{TupleKey.key(&1), &1})

    calls
    |> Enum.reduce(held, fn %Write{} = call, store ->
      store = Map.drop(store, Enum.map(call.deletes, &TupleKey.key/1))

      Enum.reduce(call.writes, store, &Map.put(&2, TupleKey.key(&1), &1))
    end)
    |> Map.values()
    |> Enum.sort()
  end

  defp keys(tuples), do: MapSet.new(tuples, &TupleKey.key/1)

  defp at(calls, key, side) do
    Enum.find_index(calls, fn call -> Enum.any?(side.(call), &(TupleKey.key(&1) == key)) end)
  end

  # A pair of states over the same small space of keys, so that a required
  # tuple and a present one meet often enough for a difference to have both
  # sides.
  defp states do
    gen all(required <- tuples(), present <- tuples()) do
      {Enum.uniq_by(required, &TupleKey.key/1), Enum.uniq_by(present, &TupleKey.key/1)}
    end
  end

  defp tuples, do: list_of(tuple_key(), max_length: 12)

  defp tuple_key do
    gen all(
          user <- member_of(~w(user:ann user:bo user:cy)),
          relation <- member_of(~w(reader writer owner)),
          object <- member_of(~w(folder:1 folder:2 item:1)),
          condition <- one_of([constant(nil), map(context(), &%Condition{name: "while", context: &1})])
        ) do
      %TupleKey{user: user, relation: relation, object: object, condition: condition}
    end
  end

  defp context, do: map(member_of(~w(low high)), &%{"clearance" => &1})
end
