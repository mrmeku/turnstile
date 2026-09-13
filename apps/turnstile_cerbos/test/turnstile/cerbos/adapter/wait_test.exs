defmodule Turnstile.Cerbos.Adapter.WaitTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Adapter.Wait

  test "an answer that is there already comes back without waiting for it" do
    assert Wait.until(fn -> :in_force end, 50) == :in_force
  end

  test "the change is asked for again until it is in force, and the answer is what came back" do
    asks = :counters.new(1, [])

    answer =
      Wait.until(
        fn ->
          :counters.add(asks, 1, 1)
          if :counters.get(asks, 1) >= 3, do: {:ok, :in_force}
        end,
        5_000
      )

    assert answer == {:ok, :in_force}
    assert :counters.get(asks, 1) == 3
  end

  test "a change that never arrives ends the wait with the last answer rather than waiting on it" do
    assert_raise RuntimeError, ~r/was not in force within 20 ms; the last answer was false/, fn ->
      Wait.until(fn -> false end, 20)
    end
  end

  test "the interval between asks is the floor of any measurement taken this way" do
    assert Wait.interval() > 0
  end
end
