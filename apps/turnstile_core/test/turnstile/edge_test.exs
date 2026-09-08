defmodule Turnstile.EdgeTest do
  use ExUnit.Case, async: true

  alias Turnstile.Edge
  alias Turnstile.Error
  alias Turnstile.Reason

  test "convert reads each field of the spec, by atom or string key, in order" do
    spec = [name: :string, count: {:integer, :nil_ok}, kind: {:in, [:a, :b]}, note: {:string, :nil_ok}]
    map = %{"name" => "x", "kind" => "a", count: nil}
    assert {:ok, [name: "x", count: nil, kind: :a, note: nil]} = Edge.convert(map, spec, :thing, [:note])
    assert {:error, %Error.Invalid{what: :thing, detail: "missing note"}} = Edge.convert(map, spec, :thing)
    assert {:error, %Error.Invalid{detail: detail}} = Edge.convert(%{map | "kind" => "c"}, spec, :thing, [:note])
    assert detail =~ "expected one of [:a, :b]"
  end

  test "value_in refuses nil for a plain string or integer and keeps it when allowed" do
    assert {:error, %Error.Invalid{}} = Edge.value_in(nil, :string, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in(nil, :integer, :thing)
    assert {:ok, nil} = Edge.value_in(nil, {:string, :nil_ok}, :thing)
    assert {:ok, nil} = Edge.value_in(nil, {:integer, :nil_ok}, :thing)
    assert {:ok, 3} = Edge.value_in(3, :integer, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in("3", :integer, :thing)
    assert {:ok, %{any: 1}} = Edge.value_in(%{any: 1}, :any, :thing)
  end

  test "atoms and modules read back only when they exist, from either form" do
    assert {:ok, :read} = Edge.value_in("read", :atom, :thing)
    assert {:ok, :read} = Edge.value_in(:read, :atom, :thing)
    assert {:ok, nil} = Edge.value_in(nil, :atom, :thing)
    assert {:error, %Error.Invalid{detail: "unknown atom " <> _rest}} = Edge.value_in("no-such-atom-xyz", :atom, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in(1, :atom, :thing)
    assert {:ok, Edge} = Edge.value_in("Turnstile.Edge", :module, :thing)
    assert {:ok, Edge} = Edge.value_in("Elixir.Turnstile.Edge", :module, :thing)
    assert {:ok, Edge} = Edge.value_in(Edge, :module, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in(1, :module, :thing)
    assert Edge.module_out(nil) == nil
    assert Edge.module_out(Edge) == "Turnstile.Edge"
  end

  test "references and times read back from their map and ISO 8601 forms" do
    assert Edge.ref_out({:folder, 1}) == %{type: "folder", id: 1}
    assert {:ok, {:folder, 1}} = Edge.value_in(%{"type" => "folder", "id" => 1}, :ref, :thing)
    assert {:ok, {:folder, 1}} = Edge.value_in({:folder, 1}, :ref, :thing)
    assert {:error, %Error.Invalid{detail: "a reference needs" <> _rest}} = Edge.value_in(%{type: "folder"}, :ref, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in(%{type: "no-such-atom-xyz", id: 1}, :ref, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in("folder", :ref, :thing)
    at = ~U[2026-09-08 00:00:00.000001Z]
    assert {:ok, ^at} = Edge.value_in(Edge.time_out(at), :time, :thing)
    assert {:ok, ^at} = Edge.value_in(at, :time, :thing)
    assert {:error, %Error.Invalid{detail: "bad time" <> _rest}} = Edge.value_in("yesterday", :time, :thing)
    assert {:error, %Error.Invalid{}} = Edge.value_in(1, :time, :thing)
    assert Edge.time_out(nil) == nil
  end

  test "a struct field takes the struct or the map its module reads, and refuses the rest" do
    reason = Reason.allowed("r")
    assert {:ok, ^reason} = Edge.value_in(reason, {:struct, Reason}, :thing)
    assert {:ok, ^reason} = Edge.value_in(Reason.to_map(reason), {:struct, Reason}, :thing)
    assert {:error, %Error.Invalid{what: :reason}} = Edge.value_in(%{code: "allowed"}, {:struct, Reason}, :thing)
    assert {:error, %Error.Invalid{what: :thing, detail: detail}} = Edge.value_in("no", {:struct, Reason}, :thing)
    assert detail =~ "expected Turnstile.Reason"
  end

  test "fetch_all names the first missing key" do
    assert {:ok, [1, 2]} = Edge.fetch_all(%{"b" => 2, a: 1}, [:a, :b], :thing)
    assert {:error, %Error.Invalid{detail: "missing c"}} = Edge.fetch_all(%{a: 1}, [:a, :c], :thing)
  end
end
