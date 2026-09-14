defmodule Example.Core.OcsfTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Example.Core.Ocsf

  @now ~U[2026-09-08 12:00:00Z]

  @change %{
    operation: :update,
    kind: :role,
    target: {:role, 7},
    changes: %{role: {:member, :designator}},
    actor: {:privileged, "gil"},
    actor_kind: :privileged,
    time: @now,
    operation_id: "op-1",
    schema: Example.Assignment
  }

  @decision %{
    subject: {:user, "ann"},
    subject_kind: :user,
    operation: :read,
    object: {:document, 4},
    verdict: :allow,
    reason: :allowed,
    decider: Turnstile.Test.Fake,
    version: "fake",
    env: %{},
    exception: nil,
    time: @now,
    operation_id: "op-1"
  }

  test "a change event maps to the OCSF class of its kind and the activity of its operation" do
    record = Ocsf.change(@change)

    assert {record.category_uid, record.class_uid, record.class_name} == {3, 3005, "User Access Management"}
    assert {record.activity_id, record.activity_name} == {3, "Update"}
    assert record.type_uid == 300_503
    assert record.time == @now
    assert record.actor == %{user: %{uid: "gil", type_id: 2, type: "Admin"}}
    assert record.entity == %{type: "role", uid: "7"}

    assert record.metadata == %{
             version: Ocsf.version(),
             product: %{name: "Example", vendor_name: "Turnstile"},
             correlation_uid: "op-1"
           }

    assert record.unmapped.changes == %{role: %{before: :member, after: :designator}}
    assert record.unmapped.schema == "Example.Assignment"
  end

  test "each kind has its class and each operation its activity" do
    for {kind, class} <- [user: 3001, group: 3006, role: 3005, entity: 3004] do
      assert Ocsf.change(%{@change | kind: kind}).class_uid == class
    end

    for {operation, activity} <- [create: 1, update: 3, delete: 4] do
      assert Ocsf.change(%{@change | operation: operation}).activity_id == activity
    end
  end

  test "a decision maps to an API activity whose status is the verdict and whose duration is the call's" do
    record = Ocsf.decision(@decision, 125)

    assert {record.category_uid, record.class_uid, record.class_name} == {6, 6003, "API Activity"}
    assert {record.activity_id, record.activity_name} == {2, "Read"}
    assert record.type_uid == 600_302
    assert {record.status_id, record.status, record.severity_id} == {1, "Success", 1}
    assert record.duration == 125
    assert record.actor == %{user: %{uid: "ann", type_id: 1, type: "User"}}
    assert record.resource == %{type: "document", uid: "4"}
    assert record.api == %{operation: "read", response: %{message: "allowed"}}
    assert record.unmapped.decider == "Turnstile.Test.Fake"
    assert record.unmapped.policy_version == "fake"
  end

  test "a denial is a failure of low severity, an unnumbered operation is other, and a narrowing call is a query that succeeded" do
    denied = Ocsf.decision(%{@decision | verdict: :deny, reason: :deny_by_default, operation: :change_marking}, 1)

    assert {denied.status_id, denied.status, denied.severity_id} == {2, "Failure", 2}
    assert {denied.activity_id, denied.activity_name} == {99, "Other"}
    assert denied.api.operation == "change_marking"
    assert denied.api.response.message == "deny_by_default"

    narrowed = Ocsf.decision(%{@decision | verdict: :scoped, object: dynamic([row], row.id == 1)}, 1)
    assert narrowed.resource == %{type: "query", uid: nil}
    assert {narrowed.status_id, narrowed.status, narrowed.severity_id} == {1, "Success", 1}

    raised = Ocsf.decision(%{@decision | verdict: :deny, reason: nil, exception: %RuntimeError{}}, 1)
    assert raised.unmapped.exception == "RuntimeError"
    assert raised.api.response.message == nil
  end

  test "an object asked about by its type alone carries no id" do
    record = Ocsf.decision(%{@decision | object: {:document, nil}}, 1)

    assert record.resource == %{type: "document", uid: nil}
  end

  test "a subject of a kind the mapping does not know is an unknown user" do
    record = Ocsf.decision(%{@decision | subject: {:robot, "r2"}, subject_kind: :robot}, 1)

    assert record.actor == %{user: %{uid: "r2", type_id: 0, type: "Unknown"}}
  end
end
