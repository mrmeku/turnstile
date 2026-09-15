defmodule Example.SiemTest do
  use Example.FakeCase, async: true

  alias Example.Documents
  alias Example.Fixture
  alias Example.Siem

  test "an attached consumer maps the decision, the access, and the changes of one operation, oldest first, and answers by correlation id",
       ctx do
    siem = start_supervised!({Siem, [attach: true]})
    document = Fixture.document!(ctx.world)
    allow(ctx.rules, "dana", :change_marking, {:document, document.id})
    dana = Fixture.subject("dana")
    marking = %{categories: ["PRVCY"], controls: [:federal_only]}

    assert {:ok, _marking} = Documents.change_marking(dana, document.id, marking, operation_id: "op-9")

    assert [decision, got, preloaded, marking, %{entity: %{type: "document"}}] = Siem.records(siem, "op-9")
    assert {decision.class_uid, decision.status} == {6003, "Success"}
    assert decision.api.operation == "change_marking"
    assert {got.class_uid, got.activity_name, got.table.name} == {6005, "Read", "document"}
    assert got.unmapped.ids == [to_string(document.id)]
    assert preloaded.unmapped == got.unmapped
    assert {marking.class_uid, marking.activity_name} == {3004, "Update"}
    assert marking.entity.type == "marking"
    assert marking.actor == %{user: %{uid: "dana", type_id: 1, type: "User"}}
    assert Map.has_key?(marking.unmapped.changes, :categories)
    assert decision.metadata.version == Siem.schema_version()
    assert Enum.take(Siem.records(siem), -5) == Siem.records(siem, "op-9")
    assert Siem.records(siem, "op-3") == []
    :ok = stop_supervised!(Siem)
  end
end
