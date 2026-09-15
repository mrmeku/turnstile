defmodule Example.Domain.BannerTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Example.Domain.Banner
  alias Example.Domain.Controls

  @countries ~w(AU CA FR GB US)

  property "a document's banner admits no subject a portion of it denies" do
    check all(markings <- markings()) do
      banner = Banner.of(markings)

      for marking <- markings, do: assert(Banner.covers?(banner, marking))
    end
  end

  property "categories and controls are the union of the portions'" do
    check all(markings <- markings()) do
      banner = Banner.of(markings)

      for field <- [:categories, :controls] do
        values = Enum.flat_map(markings, & &1[field])

        assert banner[field] == Enum.sort(Enum.uniq(values))
      end
    end
  end

  property "a country one portion withholds is released by no banner" do
    check all(markings <- markings()) do
      releasing = Enum.filter(markings, &(:releasable_to in &1.controls))
      released = Enum.filter(@countries, fn country -> Enum.all?(releasing, &(country in &1.releasable_to)) end)

      assert Banner.of(markings).releasable_to == if(releasing == [], do: [], else: released)
    end
  end

  property "the portions' order is not the banner's, and a portion counted twice changes nothing" do
    check all(markings <- markings(), extra <- marking()) do
      assert Banner.of(Enum.reverse(markings)) == Banner.of(markings)
      assert Banner.of([extra | markings] ++ [extra]) == Banner.of([extra | markings])
    end
  end

  property "a portion added to a document never widens its banner" do
    check all(markings <- markings(), extra <- marking()) do
      assert Banner.covers?(Banner.of([extra | markings]), Banner.of(markings))
    end
  end

  property "a marking covers itself, and a banner over a banner covers what the inner one covers" do
    check all([one, two, three] <- list_of(marking(), length: 3)) do
      middle = Banner.of([one, two])
      wide = Banner.of([middle, three])

      assert Banner.covers?(one, one)
      assert Banner.covers?(wide, one)
    end
  end

  property "a marking is its fields, sorted and without repeats, and reading it again changes nothing" do
    check all(row <- row()) do
      marking = Banner.marking(row)

      assert Enum.sort(Map.keys(marking)) == Enum.sort(Controls.fields())
      assert Banner.marking(marking) == marking

      for field <- Controls.fields() do
        values = marking[field]
        assert values == Enum.sort(Enum.uniq(values))
      end
    end
  end

  defp markings, do: list_of(marking(), max_length: 4)

  defp marking, do: map(row(), &Banner.marking/1)

  defp row do
    fixed_map(%{
      categories: list_of(member_of(~w(CTI PRVCY PROPIN)), max_length: 3),
      controls: list_of(member_of(Controls.all()), max_length: 3),
      releasable_to: list_of(member_of(@countries), max_length: 3)
    })
  end

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
