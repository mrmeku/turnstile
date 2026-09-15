defmodule Example.Scenarios.Enforcement do
  @moduledoc "The enforcement scenarios, enf-01 to enf-18."

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios.Support,
      Turnstile,
      Turnstile.Test,
      ExUnit
    ]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Document
  alias Example.Documents
  alias Example.Fixture
  alias Turnstile.Test.Clock

  @spec enf_01() :: term()
  def enf_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert_read(subject("ann"), document)
  end

  @spec enf_02() :: term()
  def enf_02 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert_denied(subject("frank"), document)
  end

  @spec enf_03() :: term()
  def enf_03 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert_read(subject("dana"), document)
  end

  @spec enf_04() :: term()
  def enf_04 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only])

    settle()
    assert_read(subject("ann"), document)
    assert_denied(subject("bob"), document)
  end

  @spec enf_05() :: term()
  def enf_05 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:no_foreign])

    settle()
    assert_read(subject("ann"), document)
    assert_denied(subject("carl"), document)
  end

  @spec enf_06() :: term()
  def enf_06 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:releasable_to], releasable_to: ["FR", "GB"])

    settle()
    assert_read(subject("carl"), document)
    assert_denied(subject("ann"), document)
  end

  @spec enf_07() :: term()
  def enf_07 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:named_list], list: ["ann"])

    settle()
    assert_read(subject("ann"), document)
    assert_denied(subject("bob"), document)
  end

  @spec enf_08() :: term()
  def enf_08 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only, :no_foreign])

    settle()
    assert_read(subject("ann"), document)
    assert_denied(subject("carl"), document)
    assert_denied(subject("bob"), document)
  end

  @spec enf_09() :: term()
  def enf_09 do
    world = Fixture.world!()
    document = Fixture.document!(world, categories: ["PRVCY"])
    assert document.marking.controls == []

    settle()
    assert_read(subject("ann"), document)
    assert_denied(subject("bob"), document)
    unspecified = Fixture.document!(world, categories: ["PROPIN"])

    settle()
    assert_read(subject("bob"), unspecified)
  end

  @spec enf_10() :: term()
  def enf_10 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    for id <- ["ann", "bob", "carl"], do: assert_read(subject(id), document)
  end

  @spec enf_11() :: term()
  def enf_11 do
    world = Fixture.world!()

    document =
      Fixture.document!(world, portions: [%{body: "open"}, %{body: "domestic", controls: [:no_foreign]}])

    [open, domestic] = document.portions

    settle()
    assert_denied(subject("carl"), document)
    assert {:ok, %Document{portions: portions}} = Documents.read_redacted(subject("carl"), document.id)
    assert Enum.map(portions, & &1.id) == [open.id]
    assert {:ok, %Document{portions: portions}} = Documents.read_redacted(subject("ann"), document.id)
    assert Enum.map(portions, & &1.id) == [open.id, domestic.id]
    assert_refused(Documents.read_redacted(subject("frank"), document.id), :read_redacted)
  end

  @spec enf_12() :: term()
  def enf_12 do
    world = Fixture.world!()
    document = Fixture.document!(world, portions: [%{body: "domestic", controls: [:no_foreign]}])
    dropped = %{controls: []}

    settle()

    assert {:error, %Documents.BannerViolation{portions: %{controls: [:no_foreign]}}} =
             Documents.change_marking(subject("dana"), document.id, dropped, fresh())

    assert {:ok, %Document{marking: %{controls: [:no_foreign]}}} = Documents.read(subject("dana"), document.id)
    wider = %{controls: [:no_foreign, :federal_only]}

    assert {:ok, %Example.Marking{controls: controls}} =
             Documents.change_marking(subject("dana"), document.id, wider, fresh())

    assert Enum.sort(controls) == [:federal_only, :no_foreign]
  end

  @spec enf_13() :: term()
  def enf_13 do
    world = Fixture.world!()
    past = DateTime.shift(DateTime.utc_now(), hour: -1)
    document = Fixture.document!(world, controls: [:federal_only], decontrol: past)

    settle()
    assert_read(subject("bob"), document)
  end

  @spec enf_14() :: term()
  def enf_14 do
    world = Fixture.world!()
    decontrol = DateTime.utc_now(:second)
    document = Fixture.document!(world, controls: [:federal_only], decontrol: decontrol)
    _at = Clock.set(DateTime.shift(decontrol, second: -1))

    settle()
    assert_denied(subject("bob"), document)
    _at = Clock.set(DateTime.shift(decontrol, second: 1))
    assert_read(subject("bob"), document)
  end

  @spec enf_15() :: term()
  def enf_15 do
    world = Fixture.world!()
    past = DateTime.shift(DateTime.utc_now(), hour: -1)
    document = Fixture.document!(world, controls: [:federal_only], decontrol: past)

    settle()
    assert_denied(subject("frank"), document)
  end

  @spec enf_16() :: term()
  def enf_16 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:named_list], list: ["frank"])

    settle()
    assert_denied(subject("frank"), document)
  end

  @spec enf_17() :: term()
  def enf_17 do
    world = Fixture.world!()
    domestic = Fixture.document!(world)
    foreign = Fixture.document!(world, program: world.foreign_program, office: world.foreign_office)

    settle()
    assert listed(subject("ann")) == [domestic.id]
    refute reads?(subject("ann"), foreign)
    assert listed(subject("ivan")) == [foreign.id]
    assert_read(subject("ivan"), foreign)
  end

  @spec enf_18() :: term()
  def enf_18 do
    world = Fixture.world!()

    document =
      Fixture.document!(world,
        portions: [
          %{body: "allied", controls: [:releasable_to], releasable_to: ["FR", "US"]},
          %{body: "domestic", controls: [:releasable_to], releasable_to: ["US"]}
        ]
      )

    [allied, domestic] = document.portions

    settle()
    assert_denied(subject("carl"), document)
    assert {:ok, %Document{portions: portions}} = Documents.read_redacted(subject("carl"), document.id)
    assert Enum.map(portions, & &1.id) == [allied.id]
    assert_read(subject("ann"), document)
    assert {:ok, %Document{portions: portions}} = Documents.read_redacted(subject("ann"), document.id)
    assert Enum.map(portions, & &1.id) == [allied.id, domestic.id]
  end

  defp listed(subject) do
    subject
    |> Documents.list()
    |> Enum.map(& &1.id)
  end
end
