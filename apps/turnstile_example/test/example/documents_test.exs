defmodule Example.DocumentsTest do
  use Example.FakeCase, async: true

  alias Example.Document
  alias Example.Documents
  alias Example.Fixture
  alias Example.Marking
  alias Example.Portion
  alias Turnstile.Error

  @ann %Turnstile.Subject{id: "ann", kind: :user}
  @dana %Turnstile.Subject{id: "dana", kind: :user}
  @gil %Turnstile.Subject{id: "gil", kind: :privileged}

  setup %{world: world} do
    document = Fixture.document!(world, portions: [%{body: "open"}, %{body: "domestic", controls: [:no_foreign]}])
    {:ok, document: document}
  end

  test "read returns the document with its marking under an allow, and the refusal under a deny", ctx do
    assert {:error, %Error.NotAuthorized{operation: :read}} = Documents.read(@ann, ctx.document.id)
    allow(ctx.rules, "ann", :read, {:document, ctx.document.id})
    assert {:ok, %Document{marking: %Marking{controls: [:no_foreign]}}} = Documents.read(@ann, ctx.document.id)
    assert {:error, %Error.NotAuthorized{}} = Documents.read(@ann, ctx.document.id + 1000)
    allow(ctx.rules, "ann", :read, {:document, :any})
    assert {:error, :not_found} = Documents.read(@ann, ctx.document.id + 1000)
  end

  test "read_redacted returns the portions the portion scope admits", ctx do
    [open, domestic] = ctx.document.portions
    allow(ctx.rules, "ann", :read_redacted, {:document, ctx.document.id})
    allow(ctx.rules, "ann", :read, {:portion, open.id})
    assert {:ok, %Document{portions: [%Portion{id: id}]}} = Documents.read_redacted(@ann, ctx.document.id)
    assert id == open.id
    allow(ctx.rules, "ann", :read, {:portion, domestic.id})
    assert {:ok, %Document{portions: [_open, _domestic]}} = Documents.read_redacted(@ann, ctx.document.id)
  end

  test "list returns what the document scope admits, oldest first", ctx do
    other = Fixture.document!(ctx.world, title: "other")
    assert Documents.list(@ann) == []
    allow(ctx.rules, "ann", :read, {:document, other.id})
    assert [%Document{id: id, marking: %Marking{}}] = Documents.list(@ann)
    assert id == other.id
    allow(ctx.rules, "ann", :read, {:document, :any})
    assert Enum.map(Documents.list(@ann), & &1.id) == [ctx.document.id, other.id]
  end

  test "change_marking keeps the banner over the portions", ctx do
    allow(ctx.rules, "dana", :change_marking, {:document, ctx.document.id})

    assert {:error, %Documents.BannerViolation{portions: %{controls: [:no_foreign]}}} =
             Documents.change_marking(@dana, ctx.document.id, %{controls: []})

    assert {:ok, %Marking{controls: controls, categories: ["CTI"]}} =
             Documents.change_marking(@dana, ctx.document.id, %{
               controls: [:federal_only, :no_foreign],
               categories: ["CTI"]
             })

    assert Enum.sort(controls) == [:federal_only, :no_foreign]
    assert {:error, %Error.NotAuthorized{}} = Documents.change_marking(@ann, ctx.document.id, %{controls: []})
  end

  test "set_decontrol and decontrol write the date under their own operations", ctx do
    at = ~U[2026-01-01 00:00:00.123456Z]
    assert {:error, %Error.NotAuthorized{operation: :set_decontrol}} = Documents.set_decontrol(@dana, ctx.document.id, at)
    allow(ctx.rules, "dana", :set_decontrol, {:document, ctx.document.id})
    assert {:ok, %Document{decontrol: ~U[2026-01-01 00:00:00Z]}} = Documents.set_decontrol(@dana, ctx.document.id, at)
    assert {:error, %Error.NotAuthorized{operation: :decontrol}} = Documents.decontrol(@dana, ctx.document.id)
    allow(ctx.rules, "dana", :decontrol, {:document, ctx.document.id})
    assert {:ok, %Document{decontrol: %DateTime{} = now}} = Documents.decontrol(@dana, ctx.document.id)
    assert DateTime.diff(DateTime.utc_now(), now, :second) in 0..5

    assert {:ok, _document} = Documents.set_decontrol(@dana, ctx.document.id, at)
    assert {:error, :not_found} = missing(ctx, at)
  end

  defp missing(ctx, at) do
    allow(ctx.rules, "dana", :set_decontrol, {:document, :any})
    allow(ctx.rules, "dana", :decontrol, {:document, :any})
    assert {:error, :not_found} = Documents.decontrol(@dana, ctx.document.id + 1000)
    Documents.set_decontrol(@dana, ctx.document.id + 1000, at)
  end

  test "change_portion_marking needs the portion's and the document's operation and widens the banner", ctx do
    [open, _domestic] = ctx.document.portions
    attrs = %{controls: [:federal_only]}

    assert {:error, %Error.NotAuthorized{object: {:portion, _id}}} =
             Documents.change_portion_marking(@dana, open.id, attrs)

    allow(ctx.rules, "dana", :change_marking, {:portion, open.id})

    assert {:error, %Error.NotAuthorized{object: {:document, _id}}} =
             Documents.change_portion_marking(@dana, open.id, attrs)

    allow(ctx.rules, "dana", :change_marking, {:document, ctx.document.id})
    assert {:ok, %Portion{controls: [:federal_only]}} = Documents.change_portion_marking(@dana, open.id, attrs)
    allow(ctx.rules, "dana", :read, {:document, ctx.document.id})
    assert {:ok, %Document{marking: %Marking{controls: controls}}} = Documents.read(@dana, ctx.document.id)
    assert Enum.sort(controls) == [:federal_only, :no_foreign]
    allow(ctx.rules, "dana", :change_marking, {:portion, :any})
    assert {:error, :not_found} = Documents.change_portion_marking(@dana, open.id + 1000, attrs)
  end

  test "override_read needs a privileged kind, a justification, and the permission, and reports itself", ctx do
    id = ctx.document.id
    assert {:error, %Documents.OverrideRefused{reason: :not_privileged}} = Documents.override_read(@ann, id, "why")
    assert {:error, %Documents.OverrideRefused{reason: :no_justification}} = Documents.override_read(@gil, id, "")
    hana = %Turnstile.Subject{id: "hana", kind: :privileged}
    assert {:error, %Documents.OverrideRefused{reason: :no_permission}} = Documents.override_read(hana, id, "why")
    assert {:error, :not_found} = Documents.override_read(@gil, id + 1000, "why")
    _ref = :telemetry_test.attach_event_handlers(self(), [Documents.override_event()])
    assert {:ok, %Document{id: ^id, marking: %Marking{}}} = Documents.override_read(@gil, id, "why", operation_id: "op-1")
    assert_received {[:example, :override, :read], _ref, %{}, %{subject: %{id: "gil"}, report: report}}
    assert report.operation_id == "op-1"

    assert [%{user_id: "gil", justification: "why", operation_id: "op-1"}] =
             Documents.override_reports(ctx.world.office.id)
  end

  test "operations and object references are as declared" do
    assert Documents.operations() == [
             :read,
             :read_redacted,
             :change_marking,
             :set_decontrol,
             :decontrol,
             :propose_marking
           ]

    assert Documents.object(3) == %Turnstile.Object{type: :document, id: 3}
    assert Documents.object(:portion, 4) == %Turnstile.Object{type: :portion, id: 4}
    assert Documents.override_event() == [:example, :override, :read]
  end
end
