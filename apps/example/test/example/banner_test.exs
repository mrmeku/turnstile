defmodule Example.BannerTest do
  use ExUnit.Case, async: true

  alias Example.Banner

  test "a marking is the three fields, sorted and without repeats" do
    row = %{
      categories: ["CTI", "PRVCY", "CTI"],
      controls: [:no_foreign, :federal_only],
      releasable_to: ["GB", "FR"],
      other: 1
    }

    assert Banner.marking(row) == %{
             categories: ["CTI", "PRVCY"],
             controls: [:federal_only, :no_foreign],
             releasable_to: ["FR", "GB"]
           }

    assert Banner.marking(%{}) == %{categories: [], controls: [], releasable_to: []}
  end

  test "the banner over rows carries their categories and controls and the countries all of them release to" do
    wide = %{controls: [:releasable_to], releasable_to: ["FR", "GB", "US"], categories: ["CTI"]}
    narrow = %{controls: [:releasable_to, :no_foreign], releasable_to: ["GB", "US"]}

    assert Banner.of([wide, narrow]) == %{
             categories: ["CTI"],
             controls: [:no_foreign, :releasable_to],
             releasable_to: ["GB", "US"]
           }

    assert Banner.of([]) == %{categories: [], controls: [], releasable_to: []}
  end

  test "a banner covers a marking when it carries every category and control the marking does" do
    banner = %{controls: [:no_foreign, :federal_only], categories: ["CTI"]}

    assert Banner.covers?(banner, %{controls: [:no_foreign]})
    refute Banner.covers?(%{controls: [:no_foreign]}, banner)
  end

  test "a banner covers a marking with REL TO when it releases to no country outside the marking's list" do
    marking = %{controls: [:releasable_to], releasable_to: ["US"]}

    assert Banner.covers?(%{controls: [:releasable_to], releasable_to: ["US"]}, marking)
    refute Banner.covers?(%{controls: [:releasable_to], releasable_to: ["FR", "US"]}, marking)
  end
end
