defmodule Turnstile.TestTest do
  use ExUnit.Case, async: true

  test "poll returns the first truthy value and raises after the deadline" do
    counter = :counters.new(1, [])

    assert 3 =
             Turnstile.Test.poll(fn ->
               :counters.add(counter, 1, 1)
               if :counters.get(counter, 1) >= 3, do: :counters.get(counter, 1)
             end)

    assert_raise RuntimeError, ~r/poll timed out/, fn -> Turnstile.Test.poll(fn -> nil end, 30) end
  end
end
