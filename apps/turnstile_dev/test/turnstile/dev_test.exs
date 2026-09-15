defmodule Turnstile.DevTest do
  use ExUnit.Case, async: true

  test "poll returns the first truthy value and raises after the deadline" do
    counter = :counters.new(1, [])

    assert 3 =
             Turnstile.Dev.poll(fn ->
               :counters.add(counter, 1, 1)
               if :counters.get(counter, 1) >= 3, do: :counters.get(counter, 1)
             end)

    assert_raise RuntimeError, ~r/poll timed out/, fn -> Turnstile.Dev.poll(fn -> nil end, 30) end
  end
end
