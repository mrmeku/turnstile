defmodule Turnstile.Fga.Conformance.MappingTest do
  use ExUnit.Case, async: true

  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Probe
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fixture.World
  alias Turnstile.Ledger.Fold

  defp fold(events), do: Fold.fold(events)

  test "the object types are the ones this mapping writes tuples for" do
    assert Mapping.object_types() == ["clearance", "folder"]
  end

  test "a membership becomes the account holding its role on the folder" do
    fold = fold([Probe.granted("ann", 1, :reader)])

    assert Mapping.tuples(fold, "folder:1") == [%TupleKey{user: "user:ann", relation: "reader", object: "folder:1"}]
  end

  test "a folder tuple carries the account's clearance as its condition" do
    fold = fold([Probe.granted("ann", 1, :reader), Probe.clearance("ann", nil, World.cleared())])

    assert [%TupleKey{condition: %Condition{name: "while_cleared", context: context}}] =
             Mapping.tuples(fold, "folder:1")

    assert context == %{"clearance" => World.cleared()}
  end

  test "a clearance becomes the account holding membership of the clearance itself" do
    fold = fold([Probe.clearance("ann", nil, World.cleared())])

    assert Mapping.tuples(fold, "clearance:cleared") == [
             %TupleKey{user: "user:ann", relation: "member", object: "clearance:cleared"}
           ]

    assert Mapping.tuples(fold, "clearance:secret") == []
  end

  test "a role that changed states the new relation and nothing of the old" do
    events = [Probe.granted("ann", 1, :reader), Probe.changed("ann", 1, :reader, :editor)]

    assert [%TupleKey{relation: "editor"}] = Mapping.tuples(fold(events), "folder:1")
  end

  test "a membership that went states no tuple" do
    events = [Probe.granted("ann", 1, :reader), Probe.revoked("ann", 1, :reader)]

    assert Mapping.tuples(fold(events), "folder:1") == []
  end

  test "an object of a type this mapping does not write states no tuple" do
    assert Mapping.tuples(Fold.empty(), "item:10") == []
    assert Mapping.tuples(Fold.empty(), "folder") == []
  end

  test "a membership event touches the folder it names" do
    event = Probe.granted("ann", 1, :reader)

    assert Mapping.touched(fold([event]), event) == ["folder:1"]
  end

  test "a clearance event touches the clearances it moved between and the folders the fold names" do
    granted = Probe.granted("ann", 1, :reader)
    event = Probe.clearance("ann", World.cleared(), "secret")

    assert Mapping.touched(fold([granted, event]), event) == ["clearance:cleared", "clearance:secret", "folder:1"]
  end

  test "a published version touches nothing" do
    event = Probe.published("model-1")

    assert Mapping.touched(fold([event]), event) == []
  end

  test "an event about an object this mapping does not write touches nothing" do
    granted = Probe.granted("ann", 1, :reader)
    event = %{granted | object_ref: {:item, 10}}

    assert Mapping.touched(Fold.empty(), event) == []
  end
end
