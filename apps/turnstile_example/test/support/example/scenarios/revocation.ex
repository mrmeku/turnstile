defmodule Example.Scenarios.Revocation do
  @moduledoc "The revocation scenarios that need no ledger, rev-01 to rev-06."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, Turnstile, Turnstile.Test, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Accounts
  alias Example.Fixture
  alias Turnstile.PolicyVersion

  @spec rev_01() :: term()
  def rev_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert_read(subject("ann"), document)
    started = System.monotonic_time(:millisecond)
    assert 1 = Accounts.unassign("ann", world.program.id)
    committed = System.monotonic_time(:millisecond)
    settled = settle()
    polled = System.monotonic_time(:millisecond)
    assert Turnstile.Test.poll(fn -> not reads?(subject("ann"), document) end)
    finished = System.monotonic_time(:millisecond)

    latency_report(
      total: finished - started,
      commit: committed - started,
      drain: drain(settled, polled - committed),
      poll: finished - polled
    )

    assert_denied(subject("ann"), document)
  end

  @spec rev_02() :: term()
  def rev_02 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:named_list], list: ["ann", "bob"])

    settle()
    assert_read(subject("bob"), document)
    _marking = Fixture.set_list!(document, ["ann"])

    settle()
    assert_denied(subject("bob"), document)
    assert_read(subject("ann"), document)
  end

  @spec rev_03() :: term()
  def rev_03 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only])

    settle()
    assert_read(subject("ann"), document)
    _user = Accounts.set_employment("ann", :contractor)

    settle()
    assert_denied(subject("ann"), document)
  end

  @spec rev_04() :: term()
  def rev_04 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:no_foreign])

    settle()
    assert_denied(subject("carl"), document)
    _user = Accounts.set_nationality("carl", "US")

    settle()
    assert_read(subject("carl"), document)
    _user = Accounts.set_nationality("ann", "FR")

    settle()
    assert_denied(subject("ann"), document)
  end

  @spec rev_05() :: term()
  def rev_05 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    for id <- ["ann", "bob", "carl"], do: assert_read(subject(id), document)
    _program = Fixture.close_program!(world.program)

    settle()
    for id <- ["ann", "bob", "carl"], do: assert_denied(subject(id), document)
    assert_read(subject("dana"), document)
  end

  @spec rev_06(module()) :: term()
  def rev_06(rules) do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert_read(subject("ann"), document)
    started = System.monotonic_time(:millisecond)
    assert {:ok, %PolicyVersion{version: version}} = rules.publish_tightened()
    published = System.monotonic_time(:millisecond)

    try do
      polled = System.monotonic_time(:millisecond)
      assert Turnstile.Test.poll(fn -> not reads?(subject("ann"), document) end)
      finished = System.monotonic_time(:millisecond)
      propagation_report(version, total: finished - started, publish: published - started, poll: finished - polled)
      assert_denied(subject("ann"), document)
      assert_read(subject("dana"), document)
    after
      :ok = rules.restore()
    end

    assert_read(subject("ann"), document)
  end

  # The share of the latency that reached the engine's own store: what the
  # drain took, where there was one to wait for.
  defp drain(:none, _milliseconds), do: nil
  defp drain(:ok, milliseconds), do: milliseconds
end
