defmodule Turnstile.Test.SettleTest do
  use ExUnit.Case, async: true

  alias Turnstile.Adapter.Fake
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.Ledger.Memory
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.Test.LedgerAdapter
  alias Turnstile.Test.Projection

  @at ~U[2026-09-09 12:00:00.000000Z]

  setup do
    ledger = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})
    agent = start_supervised!(%{id: Projection, start: {Projection, :start_link, []}})
    options = [agent: ledger]

    {:ok, ledger: {Memory, options}, projection: %Projection{agent: agent, ledger: {Memory, options}}}
  end

  test "an adapter that declares no projection has nothing to settle", context do
    :ok = Test.with_config(adapter: {Fake, rules: self()}, ledger: context.ledger)
    :ok = appended(context, 3)

    assert Test.settle() == :none
  end

  test "settling drains the projection to the ledger's head", context do
    :ok = bound(context)
    :ok = appended(context, 3)

    assert Test.settle() == :ok
    assert Projection.checkpoint(context.projection) == {:ok, 3}
    assert map_size(Projection.facts(context.projection)) == 3

    :ok = appended(context, 2)

    assert Test.settle() == :ok
    assert Projection.checkpoint(context.projection) == {:ok, 5}
  end

  test "settling an empty ledger is the drain that applies nothing", context do
    :ok = bound(context)

    assert Test.settle() == :ok
    assert Projection.checkpoint(context.projection) == {:ok, 0}
  end

  test "settling more than the batch reaches the head", context do
    :ok = bound(context, batch: 2)
    :ok = appended(context, 5)

    assert Test.settle() == :ok
    assert Projection.checkpoint(context.projection) == {:ok, 5}
  end

  test "a drain that fails raises what it failed with", context do
    :ok = bound(context, interrupt_after: 1)
    :ok = appended(context, 3)

    assert_raise Error.Engine, ~r/interrupted after 1 of 3 events/, fn -> Test.settle() end
  end

  defp bound(context, overrides \\ []) do
    :ok = Test.with_config(adapter: {LedgerAdapter, rules: self()}, ledger: context.ledger)
    LedgerAdapter.bind(struct!(context.projection, overrides))
  end

  defp appended(%{ledger: {module, options}}, count) do
    events =
      for index <- 1..count do
        %FactEvent{
          kind: :object_attribute,
          subject_ref: nil,
          object_ref: {:folder, index},
          attribute: :label,
          old: nil,
          new: "secret",
          position: nil,
          operation_id: Id.new(),
          at: @at,
          by: %Subject{id: "ann", kind: :user}
        }
      end

    {:ok, _stamped} = module.append(options, events)

    :ok
  end
end
