defmodule Turnstile.Test.SettleTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Test
  alias Turnstile.Test.Fake
  alias Turnstile.Test.SettlingAdapter

  test "an adapter that keeps no state of its own has nothing to settle" do
    :ok = Test.with_config(adapter: {Fake, rules: self()})

    assert Test.settle() == :none
  end

  test "an adapter that declares the callback and nothing to settle answers none" do
    :ok = Test.with_config(adapter: {SettlingAdapter, rules: self()})

    assert Test.settle() == :none
  end

  test "settling is the adapter's own, and its answer is the answer" do
    :ok =
      bound(fn ->
        send(self(), :settled)

        :ok
      end)

    assert Test.settle() == :ok
    assert_received :settled
  end

  test "a settle that fails raises what it failed with" do
    :ok = bound(fn -> {:error, Error.invalid(:outbox, "the store is out of reach")} end)

    assert_raise Error, ~r/the store is out of reach/, fn -> Test.settle() end
  end

  defp bound(settling) do
    :ok = Test.with_config(adapter: {SettlingAdapter, rules: self()})
    SettlingAdapter.bind(settling)
  end
end
