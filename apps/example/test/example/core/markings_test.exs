defmodule Example.Core.MarkingsTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias Example.Controls
  alias Example.Core.Markings

  @countries ~w(AU CA FR GB US)

  property "a document's banner admits no subject a portion of it denies" do
    check all(markings <- markings()) do
      banner = Markings.banner(markings)

      for marking <- markings, do: assert(Markings.covers?(banner, marking))
    end
  end

  property "categories and controls are the union of the portions'" do
    check all(markings <- markings()) do
      banner = Markings.banner(markings)

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

      assert Markings.banner(markings).releasable_to == if(releasing == [], do: [], else: released)
    end
  end

  property "the portions' order is not the banner's, and a portion counted twice changes nothing" do
    check all(markings <- markings(), extra <- marking()) do
      assert Markings.banner(Enum.reverse(markings)) == Markings.banner(markings)
      assert Markings.banner([extra | markings] ++ [extra]) == Markings.banner([extra | markings])
    end
  end

  property "a portion added to a document never widens its banner" do
    check all(markings <- markings(), extra <- marking()) do
      assert Markings.covers?(Markings.banner([extra | markings]), Markings.banner(markings))
    end
  end

  property "a marking covers itself, and a banner over a banner covers what the inner one covers" do
    check all([one, two, three] <- list_of(marking(), length: 3)) do
      middle = Markings.banner([one, two])
      wide = Markings.banner([middle, three])

      assert Markings.covers?(one, one)
      assert Markings.covers?(wide, one)
    end
  end

  property "a marking is its fields, sorted and without repeats, and reading it again changes nothing" do
    check all(row <- row()) do
      marking = Markings.marking(row)

      assert Enum.sort(Map.keys(marking)) == Enum.sort(Controls.fields())
      assert Markings.marking(marking) == marking

      for field <- Controls.fields() do
        values = marking[field]
        assert values == Enum.sort(Enum.uniq(values))
      end
    end
  end

  defp markings, do: list_of(marking(), max_length: 4)

  defp marking, do: map(row(), &Markings.marking/1)

  defp row do
    fixed_map(%{
      categories: list_of(member_of(~w(CTI PRVCY PROPIN)), max_length: 3),
      controls: list_of(member_of(Controls.all()), max_length: 3),
      releasable_to: list_of(member_of(@countries), max_length: 3)
    })
  end
end
