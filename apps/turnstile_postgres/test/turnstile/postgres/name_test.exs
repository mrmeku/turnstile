defmodule Turnstile.Postgres.NameTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Postgres.Name

  test "a plain lowercase identifier passes, as an atom or as text" do
    assert Name.check!("turnstile_fixture_folders", :table) == "turnstile_fixture_folders"
    assert Name.check!(:read, :operation) == "read"
    assert Name.check!("a1_2", :table) == "a1_2"
  end

  test "anything that would need quoting is refused, and the error names what was being named" do
    for refused <- ["Folders", "folders; drop table x", "folder-1", "1folder", "", "folders\"x"] do
      assert_raise Error.Invalid, fn -> Name.check!(refused, :table) end
    end

    assert %Error.Invalid{what: :policy} = catch_error(Name.check!("A", :policy))
  end

  test "a name longer than the identifier limit is refused" do
    assert_raise Error.Invalid, fn -> Name.check!(String.duplicate("a", 64), :table) end
    assert Name.check!(String.duplicate("a", 63), :table) == String.duplicate("a", 63)
  end
end
