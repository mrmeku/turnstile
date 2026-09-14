defmodule Turnstile.Test.SettleTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Ledger.Memory
  alias Turnstile.Test
  alias Turnstile.Test.Fake
  alias Turnstile.Test.LedgerAdapter

  setup do
    ledger = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})

    {:ok, ledger: {Memory, agent: ledger}}
  end

  test "an adapter that keeps no state of its own has nothing to settle", context do
    :ok = Test.with_config(adapter: {Fake, rules: self()}, ledger: context.ledger)

    assert Test.settle() == :none
  end

  test "an adapter that declares the callback and nothing to settle answers none", context do
    :ok = Test.with_config(adapter: {LedgerAdapter, rules: self()}, ledger: context.ledger)

    assert Test.settle() == :none
  end

  test "settling is the adapter's own, and its answer is the answer", context do
    :ok =
      bound(context, fn ->
        send(self(), :settled)

        :ok
      end)

    assert Test.settle() == :ok
    assert_received :settled
  end

  test "a settle that fails raises what it failed with", context do
    :ok = bound(context, fn -> {:error, Error.invalid(:outbox, "the store is out of reach")} end)

    assert_raise Error, ~r/the store is out of reach/, fn -> Test.settle() end
  end

  defp bound(context, settling) do
    :ok = Test.with_config(adapter: {LedgerAdapter, rules: self()}, ledger: context.ledger)
    LedgerAdapter.bind(settling)
  end
end
