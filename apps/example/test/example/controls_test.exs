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

  test "the banner carries every category and every control of the markings under it" do
    banner = Controls.banner([%{controls: [:no_foreign]}, %{controls: [:federal_only], categories: ["CTI"]}])
    assert banner == %{categories: ["CTI"], controls: [:federal_only, :no_foreign], releasable_to: []}
    assert Controls.banner([]) == %{categories: [], controls: [], releasable_to: []}
  end

  test "the banner releases to the countries every marking that carries REL TO releases to" do
    wide = %{controls: [:releasable_to], releasable_to: ["FR", "GB", "US"]}
    narrow = %{controls: [:releasable_to], releasable_to: ["GB", "US"]}

    assert Controls.banner([wide, narrow]) == %{
             categories: [],
             controls: [:releasable_to],
             releasable_to: ["GB", "US"]
           }
  end

  test "a marking without REL TO narrows no country list, and one with an unmet list releases to nobody" do
    released = %{controls: [:releasable_to], releasable_to: ["FR"]}
    open = %{controls: [:no_foreign]}

    assert Controls.banner([released, open]) == %{
             categories: [],
             controls: [:no_foreign, :releasable_to],
             releasable_to: ["FR"]
           }

    assert Controls.banner([released, %{controls: [:releasable_to], releasable_to: ["US"]}]) == %{
             categories: [],
             controls: [:releasable_to],
             releasable_to: []
           }
  end

  test "the banner covers every marking it was built from" do
    markings = [
      %{controls: [:releasable_to], releasable_to: ["FR", "US"], categories: ["CTI"]},
      %{controls: [:releasable_to, :no_foreign], releasable_to: ["US"]},
      %{categories: ["PRVCY"]}
    ]

    banner = Controls.banner(markings)
    for marking <- markings, do: assert(Controls.covers?(banner, marking))
  end

  test "a banner covers a marking when it carries every category and control the marking does" do
    banner = %{controls: [:no_foreign, :federal_only], categories: ["CTI"], releasable_to: []}
    assert Controls.covers?(banner, %{controls: [:no_foreign]})
    refute Controls.covers?(%{controls: [:no_foreign]}, banner)
  end

  test "a banner covers a marking with REL TO when it releases to no country outside the marking's list" do
    marking = %{controls: [:releasable_to], releasable_to: ["US"]}
    assert Controls.covers?(%{controls: [:releasable_to], releasable_to: ["US"]}, marking)
    assert Controls.covers?(%{controls: [:releasable_to], releasable_to: []}, marking)
    refute Controls.covers?(%{controls: [:releasable_to], releasable_to: ["FR", "US"]}, marking)
    refute Controls.covers?(%{controls: [], releasable_to: ["US"]}, marking)
  end

  test "the controls and the fields are the committed lists" do
    assert Controls.all() == [:federal_only, :no_foreign, :named_list, :releasable_to]
    assert Controls.fields() == [:categories, :controls, :releasable_to]
  end
end
