defmodule Example.Domain.ControlsTest do
  use ExUnit.Case, async: true

  alias Example.Domain.Controls

  test "the controls and the fields are the committed lists" do
    assert Controls.all() == [:federal_only, :no_foreign, :named_list, :releasable_to]
    assert Controls.fields() == [:categories, :controls, :releasable_to]
  end
end
