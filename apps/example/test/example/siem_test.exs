defmodule Example.SiemTest do
  use Example.FakeCase, async: true

  alias Example.Documents
  alias Example.Fixture
  alias Example.Siem

  test "an unattached consumer holds what it is told, oldest first, and answers by correlation id" do
    siem = start_supervised!({Siem, []})
    :ok = Siem.record(siem, record(3005, "op-1"))
    :ok = Siem.record(siem, record(6003, "op-2"))

    assert [%{class_uid: 3005}, %{class_uid: 6003}] = Siem.records(siem)
    assert [%{class_uid: 3005}] = Siem.records(siem, "op-1")
    assert Siem.records(siem, "op-3") == []
  end

  test "an attached consumer maps the decision the port published and the change the seam did", ctx do
    siem = start_supervised!({Siem, [attach: true]})
    document = Fixture.document!(ctx.world)
    allow(ctx.rules, "dana", :change_marking, {:document, document.id})
    dana = Fixture.subject("dana")
    marking = %{categories: ["PRVCY"], controls: [:federal_only]}

    assert {:ok, _marking} = Documents.change_marking(dana, document.id, marking, operation_id: "op-9")

    assert [decision, marking, %{entity: %{type: "document"}}] = Siem.records(siem, "op-9")
    assert {decision.class_uid, decision.status} == {6003, "Success"}
    assert decision.api.operation == "change_marking"
    assert {marking.class_uid, marking.activity_name} == {3004, "Update"}
    assert marking.entity.type == "marking"
    assert marking.actor == %{user: %{uid: "dana", type_id: 1, type: "User"}}
    assert Map.has_key?(marking.unmapped.changes, :categories)
    assert decision.metadata.version == Siem.schema_version()

    assert Siem.events() == [[:turnstile, :change], [:turnstile, :decision]]
    :ok = stop_supervised!(Siem)
  end

  defp record(class, operation_id) do
    %{class_uid: class, metadata: %{correlation_uid: operation_id}}
  end
end
