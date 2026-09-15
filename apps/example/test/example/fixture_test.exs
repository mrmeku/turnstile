defmodule Example.FixtureTest do
  use Example.FakeCase, async: true

  alias Example.Fixture

  test "the world has its accounts, its two tenants, and its categories", %{world: world} do
    assert world.agency.nationality == "US" and world.foreign_agency.nationality == "FR"
    assert length(Fixture.subjects()) == 10
    assert Fixture.subject("gil") == {:privileged, "gil"}
    assert %Example.Domain.User{kind: :user, employment: :contractor} = Fixture.account!("zed", employment: :contractor)
    assert Fixture.account_ids() == ~w[ann bob carl dana eve frank gil gil-user hana ivan]
  end

  test "a document's banner carries its portions' controls", %{world: world} do
    document = Fixture.document!(world, controls: [:federal_only], portions: [%{body: "d", controls: [:no_foreign]}])
    assert Enum.sort(document.marking.controls) == [:federal_only, :no_foreign]
    assert %Example.Domain.Marking{list: ["ann"]} = Fixture.set_list!(document, ["ann"])
    assert %Example.Domain.Program{closed_at: %DateTime{}} = Fixture.close_program!(world.program)
  end

  test "a document's banner releases to no country a portion withholds", %{world: world} do
    document =
      Fixture.document!(world,
        controls: [:releasable_to],
        releasable_to: ["FR", "US"],
        portions: [%{body: "d", controls: [:releasable_to], releasable_to: ["US"]}]
      )

    assert document.marking.releasable_to == ["US"]
  end
end
