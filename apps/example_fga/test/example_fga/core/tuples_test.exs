defmodule ExampleFga.Core.TuplesTest do
  use ExUnit.Case, async: true

  alias ExampleFga.Core.Tuples

  test "a document with no marking states nothing about categories, releases, or controls" do
    assert Tuples.marking(nil, "document:1", nil) == []
  end
end
