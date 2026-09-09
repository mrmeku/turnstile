defmodule Example.ControlsTest do
  use ExUnit.Case, async: true

  alias Example.Controls

  test "a marking is the three fields, sorted and without repeats" do
    row = %{
      categories: ["CTI", "PRVCY", "CTI"],
      controls: [:no_foreign, :federal_only],
      releasable_to: ["GB", "FR"],
      other: 1
    }

    assert Controls.marking(row) == %{
             categories: ["CTI", "PRVCY"],
             controls: [:federal_only, :no_foreign],
             releasable_to: ["FR", "GB"]
           }

    assert Controls.marking(%{}) == %{categories: [], controls: [], releasable_to: []}
  end

  test "the union of markings is field-wise, and an empty list is the empty marking" do
    union = Controls.union([%{controls: [:no_foreign]}, %{controls: [:federal_only], categories: ["CTI"]}])
    assert union == %{categories: ["CTI"], controls: [:federal_only, :no_foreign], releasable_to: []}
    assert Controls.union([]) == %{categories: [], controls: [], releasable_to: []}
  end

  test "a banner covers a marking when every field of the marking is within the banner's" do
    banner = %{controls: [:no_foreign, :federal_only], categories: ["CTI"], releasable_to: []}
    assert Controls.covers?(banner, %{controls: [:no_foreign]})
    refute Controls.covers?(%{controls: [:no_foreign]}, banner)
    refute Controls.covers?(banner, %{releasable_to: ["FR"]})
  end

  test "the controls and the fields are the committed lists" do
    assert Controls.all() == [:federal_only, :no_foreign, :named_list, :releasable_to]
    assert Controls.fields() == [:categories, :controls, :releasable_to]
  end
end
