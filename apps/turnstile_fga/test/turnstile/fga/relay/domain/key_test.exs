defmodule Turnstile.Fga.Relay.Domain.KeyTest do
  use ExUnit.Case, async: true

  alias Turnstile.Fga.Relay.Domain.Key

  @limit Integer.pow(2, 31)

  test "the same runner arrives at the same key, and both halves fit what Postgres takes" do
    {class, key} = Key.of(:a_runner)

    assert Key.of(:a_runner) == {class, key}
    assert class in 0..(@limit - 1)
    assert key in 0..(@limit - 1)
  end

  test "two runners take different keys under the one class this library holds" do
    {class, first} = Key.of(:first)
    {same_class, second} = Key.of(:second)

    assert class == same_class
    assert first != second
  end
end
