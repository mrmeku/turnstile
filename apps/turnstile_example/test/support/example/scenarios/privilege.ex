defmodule Example.Scenarios.Privilege do
  @moduledoc "The least-privilege and separation-of-duties scenarios, lp-01 to lp-08 and sod-01 to sod-03."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, Turnstile, Turnstile.Test, Ecto, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Accounts
  alias Example.Document
  alias Example.Documents
  alias Example.Fixture
  alias Example.Proposals
  alias Turnstile.Error

  @noforn %{controls: [:no_foreign]}

  @spec lp_01() :: term()
  def lp_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert_read(subject("ann"), document)
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(subject("ann"), document.id, @noforn, fresh())
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("ann"), document.id)
  end

  @spec lp_02() :: term()
  def lp_02 do
    world = Fixture.world!()
    foreign = Fixture.document!(world, program: world.foreign_program, office: world.foreign_office)
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(subject("dana"), foreign.id, @noforn, fresh())
    domestic = Fixture.document!(world)
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(subject("hana"), domestic.id, @noforn, fresh())
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("dana"), domestic.id)
  end

  @spec lp_03() :: term()
  def lp_03 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    assert {:ok, %Example.Marking{controls: [:no_foreign]}} =
             Documents.change_marking(subject("dana"), document.id, @noforn, fresh())

    assert {:ok, %Document{marking: %{controls: [:no_foreign]}}} = Documents.read(subject("dana"), document.id)
  end

  @spec lp_04() :: term()
  def lp_04 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only])
    at = DateTime.shift(DateTime.utc_now(), minute: -1)
    assert {:error, %Error.NotAuthorized{}} = Documents.set_decontrol(subject("ann"), document.id, at, fresh())
    assert {:error, %Error.NotAuthorized{}} = Documents.decontrol(subject("eve"), document.id, fresh())
    assert_denied(subject("bob"), document)
    assert {:ok, %Document{decontrol: %DateTime{}}} = Documents.set_decontrol(subject("dana"), document.id, at, fresh())
    assert_read(subject("bob"), document)
  end

  @spec lp_05() :: term()
  def lp_05 do
    world = Fixture.world!()
    document = Fixture.document!(world, portions: [%{body: "open"}])
    [portion] = document.portions
    tightened = %{controls: [:no_foreign]}

    for id <- ["ann", "eve", "hana"] do
      assert {:error, %Error.NotAuthorized{}} =
               Documents.change_portion_marking(subject(id), portion.id, tightened, fresh())
    end

    assert {:ok, %Example.Portion{controls: [:no_foreign]}} =
             Documents.change_portion_marking(subject("dana"), portion.id, tightened, fresh())

    assert {:ok, %Document{marking: %{controls: [:no_foreign]}}} = Documents.read(subject("dana"), document.id)
  end

  @spec lp_06() :: term()
  def lp_06 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert_denied(subject("frank"), document)

    assert {:error, %Documents.OverrideRefused{reason: :not_privileged}} =
             Documents.override_read(subject("frank"), document.id, "incident 12")

    assert Documents.override_reports(world.office.id) == []
  end

  @spec lp_07() :: term()
  def lp_07 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:named_list], list: ["frank"])
    ordinary = subject("gil-user")
    assert ordinary.kind == :user
    assert_denied(ordinary, document)

    assert {:error, %Documents.OverrideRefused{reason: :not_privileged}} =
             Documents.override_read(ordinary, document.id, "incident 12")

    assert {:ok, %Document{}} = Documents.override_read(subject("gil"), document.id, "incident 12")
    assert [%{user_id: "gil"}] = Documents.override_reports(world.office.id)
  end

  @spec lp_08() :: term()
  def lp_08 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only])
    report = Example.Review.report(subject("eve"), fresh())
    assert report =~ "agency Domestic"
    assert report =~ "ann reads [#{document.id}]"
    assert report =~ "bob reads []"
    assert report =~ "dana may change_marking [#{document.id}]"
    assert report =~ "ann may change_marking []"
    assert report =~ "eve may change_marking []"
    assert report =~ "privileged accounts"
    assert report =~ "gil (person gil) holds [override]"
    refute report =~ "gil-user (person"
  end

  @spec sod_01() :: term()
  def sod_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert {:ok, proposal} = Proposals.propose(subject("dana"), document.id, @noforn, fresh())

    assert {:ok, %Example.Proposal{status: :approved, approver_id: "eve"}} =
             Proposals.approve(subject("eve"), proposal.id, fresh())

    assert {:ok, %Document{marking: %{controls: [:no_foreign]}}} = Documents.read(subject("dana"), document.id)
    assert {:error, :not_found} = Proposals.approve(subject("eve"), proposal.id, fresh())
  end

  @spec sod_02() :: term()
  def sod_02 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    _role = Accounts.office_role("dana", world.office.id, :approver)
    assert {:ok, proposal} = Proposals.propose(subject("dana"), document.id, @noforn, fresh())
    assert {:error, %Error.NotAuthorized{}} = Proposals.approve(subject("dana"), proposal.id, fresh())
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("dana"), document.id)
    _role = Accounts.office_role("eve", world.office.id, :designator)
    assert {:ok, other} = Proposals.propose(subject("eve"), document.id, %{controls: [:federal_only]}, fresh())

    assert {:ok, %Example.Proposal{status: :approved, approver_id: "dana"}} =
             Proposals.approve(subject("dana"), other.id, fresh())
  end

  @spec sod_03() :: term()
  def sod_03 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert {:ok, %Example.Proposal{status: :pending}} = Proposals.propose(subject("dana"), document.id, @noforn, fresh())
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("dana"), document.id)
    assert_read(subject("carl"), document)
  end
end
