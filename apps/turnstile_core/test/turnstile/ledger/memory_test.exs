defmodule Turnstile.Ledger.MemoryTest do
  use ExUnit.Case, async: true

  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory

  setup do
    {:ok, agent} = Memory.start_link()
    {:ok, options: [agent: agent]}
  end

  defp event(attribute) do
    %FactEvent{
      kind: :subject_attribute,
      subject_ref: {:user, "11111111-1111-1111-1111-111111111111"},
      object_ref: nil,
      attribute: attribute,
      old: nil,
      new: true,
      position: nil,
      operation_id: "22222222-2222-2222-2222-222222222222",
      at: ~U[2026-09-08 00:00:00Z],
      by: {:user, "11111111-1111-1111-1111-111111111111"}
    }
  end

  test "an empty ledger has head 0 and reads nothing", %{options: options} do
    assert {:ok, 0} = Memory.head(options)
    assert {:ok, []} = Memory.read(options, 0, 10)
  end

  test "append stamps consecutive positions and moves the head", %{options: options} do
    assert {:ok, [%FactEvent{position: 1}, %FactEvent{position: 2}]} = Memory.append(options, [event(:a), event(:b)])
    assert {:ok, [%FactEvent{position: 3}]} = Memory.append(options, [event(:c)])
    assert {:ok, 3} = Memory.head(options)
  end

  test "read returns events after a position, in order, up to the limit", %{options: options} do
    {:ok, _stamped} = Memory.append(options, [event(:a), event(:b), event(:c)])
    assert {:ok, [%FactEvent{position: 2, attribute: :b}, %FactEvent{position: 3}]} = Memory.read(options, 1, 10)
    assert {:ok, [%FactEvent{position: 1}]} = Memory.read(options, 0, 1)
    assert {:ok, []} = Memory.read(options, 3, 10)
  end

  test "the options schema requires the agent and defaults the lock clause", %{options: options} do
    assert {:ok, validated} = NimbleOptions.validate(options, Memory.options_schema())
    assert validated[:agent] == options[:agent]
    assert validated[:lock] == "FOR UPDATE"
    assert {:error, %NimbleOptions.ValidationError{}} = NimbleOptions.validate([], Memory.options_schema())
  end

  test "FactEvent names its kinds" do
    assert FactEvent.kinds() == [:subject_attribute, :object_attribute, :relationship, :policy_version]
  end
end
