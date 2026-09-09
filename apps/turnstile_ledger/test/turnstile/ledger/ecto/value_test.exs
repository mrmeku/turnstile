defmodule Turnstile.Ledger.Ecto.ValueTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Ledger.Ecto.Value

  test "a value sits under one key and comes back as the term that was written" do
    assert Value.dump("text") == %{"v" => "text"}
    assert Value.load(%{"v" => "text"}) == {:ok, "text"}
    assert Value.load(nil) == {:ok, nil}
  end

  test "a struct the codec has no tag for is a mistake in a fact declaration, so it raises" do
    assert_raise Error.Invalid, ~r/no encoding for Range/, fn -> Value.dump(1..2) end
  end

  test "a column holding something other than a tagged value is refused" do
    assert {:error, %Error.Invalid{what: :fact_value}} = Value.load(%{"other" => 1})
    assert {:error, %Error.Invalid{what: :fact_value}} = Value.load("bare")
    assert {:error, %Error.Invalid{what: :fact_value}} = Value.load(%{"v" => %{"unknown" => 1}})
  end

  test "a reference carries its type and its id, and comes back as the pair" do
    assert Value.ref_dump({:folder, 7}) == %{"type" => "folder", "id" => 7}
    assert Value.ref_load(%{"type" => "folder", "id" => 7}) == {:ok, {:folder, 7}}
    assert Value.ref_dump(nil) == nil
    assert Value.ref_load(nil) == {:ok, nil}
  end

  test "a column holding something other than a reference is refused" do
    assert {:error, %Error.Invalid{what: :fact_value}} = Value.ref_load(%{"type" => "folder"})
  end
end
