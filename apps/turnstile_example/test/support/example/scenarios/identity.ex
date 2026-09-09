defmodule Example.Scenarios.Identity do
  @moduledoc "The re-authentication and emergency-override scenarios, ia-01 to ia-03 and ovr-01 to ovr-03."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, Turnstile, Turnstile.Test, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Document
  alias Example.Documents
  alias Example.Fixture
  alias Turnstile.Error
  alias Turnstile.Id

  @noforn %{controls: [:no_foreign]}

  @spec ia_01() :: term()
  def ia_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()

    assert {:ok, %Example.Marking{controls: [:no_foreign]}} =
             Documents.change_marking(subject("dana"), document.id, @noforn, fresh())
  end

  @spec ia_02() :: term()
  def ia_02 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(subject("dana"), document.id, @noforn, stale())
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("dana"), document.id, stale())

    assert {:ok, %Example.Marking{controls: [:no_foreign]}} =
             Documents.change_marking(subject("dana"), document.id, @noforn, fresh())
  end

  @spec ia_03() :: term()
  def ia_03 do
    world = Fixture.world!()
    document = Fixture.document!(world)

    settle()
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(subject("dana"), document.id, @noforn)
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(subject("dana"), document.id, @noforn, facts: %{})
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("dana"), document.id)
  end

  @spec ovr_01() :: term()
  def ovr_01 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:named_list], list: ["frank"])
    gil = subject("gil")

    settle()
    assert_denied(gil, document)
    operation_id = Id.new()
    _ref = :telemetry_test.attach_event_handlers(self(), [Documents.override_event()])
    assert {:ok, %Document{id: id}} = Documents.override_read(gil, document.id, "incident 12", operation_id: operation_id)
    assert id == document.id
    event = Documents.override_event()
    assert_received {^event, _ref, %{}, %{subject: %{id: "gil", kind: "privileged"}, report: report}}
    assert report.operation_id == operation_id
    assert report.justification == "incident 12"

    assert [%{user_id: "gil", document_id: ^id, justification: "incident 12"}] =
             Documents.override_reports(world.office.id)

    assert Documents.override_reports(world.foreign_office.id) == []
  end

  @spec ovr_02() :: term()
  def ovr_02 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:named_list], list: ["frank"])
    gil = subject("gil")

    settle()
    assert {:error, %Documents.OverrideRefused{reason: :no_justification}} = Documents.override_read(gil, document.id, "")

    assert {:error, %Documents.OverrideRefused{reason: :no_justification}} =
             Documents.override_read(gil, document.id, nil)

    assert Documents.override_reports(world.office.id) == []
  end

  @spec ovr_03() :: term()
  def ovr_03 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    gil = subject("gil")

    settle()
    assert {:ok, %Document{}} = Documents.override_read(gil, document.id, "incident 12")
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(gil, document.id, @noforn, fresh())
    assert {:error, %Error.NotAuthorized{}} = Documents.decontrol(gil, document.id, fresh())
    refute Turnstile.check(gil, :change_marking, Documents.object(document.id), fresh())
    assert {:ok, %Document{marking: %{controls: []}}} = Documents.read(subject("dana"), document.id)
  end
end
