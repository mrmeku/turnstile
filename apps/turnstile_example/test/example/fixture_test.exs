defmodule Example.FixtureTest do
  use Example.FakeCase, async: true

  alias Example.Fixture
  alias Example.Fixture.Clock

  test "the world has its accounts, its two tenants, and its categories", %{world: world} do
    assert world.agency.nationality == "US" and world.foreign_agency.nationality == "FR"
    assert length(Fixture.subjects()) == 10
    assert Fixture.subject("gil").kind == :privileged
    assert %Example.User{kind: :user, employment: :contractor} = Fixture.account!("zed", employment: :contractor)
    assert Fixture.account_ids() == ~w[ann bob carl dana eve frank gil gil-user hana ivan]
  end

  test "a document gets the union of its portions' controls as its banner", %{world: world} do
    document = Fixture.document!(world, controls: [:federal_only], portions: [%{body: "d", controls: [:no_foreign]}])
    assert Enum.sort(document.marking.controls) == [:federal_only, :no_foreign]
    assert %Example.Marking{list: ["ann"]} = Fixture.set_list!(document, ["ann"])
    assert %Example.Program{closed_at: %DateTime{}} = Fixture.close_program!(world.program)
  end

  test "the clock answers what the process set and raises otherwise" do
    assert_raise RuntimeError, fn -> Clock.now() end
    :ok = Clock.set(~U[2026-09-08 12:00:00Z])
    assert Clock.now() == ~U[2026-09-08 12:00:00Z]
  end
end
