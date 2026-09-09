defmodule Turnstile.Cerbos.DecisionsTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Decisions
  alias Turnstile.Cerbos.Decisions.Line
  alias Turnstile.Cerbos.Finding
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Sidecar
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Id
  alias Turnstile.Reason
  alias Turnstile.Subject
  alias Turnstile.Test

  @principal %{id: "an-account", roles: ["user"], attr: %{"clearance" => "cleared"}}
  @resource %{kind: "folder", id: "1", attr: %{"member_roles" => ["reader"]}}

  test "the sidecar's own log reads back, and a record that disagrees with a line is a drift finding" do
    sidecar = Sidecar.own!()
    {:ok, _answered} = Client.check_resources(sidecar.address, Request.logged(@principal, @resource, ["read"]))
    {:ok, _planned} = Client.plan_resources(sidecar.address, plan_body())

    lines = Test.poll(fn -> two(sidecar.audit_log) end, 30_000)

    assert [%Line{} = checked, %Line{} = planned] = lines
    assert checked.number == 1
    assert checked.subject == "an-account"
    assert checked.operation == "read"
    assert checked.kind == "folder"
    assert checked.id == "1"
    assert checked.verdict == :allow
    assert checked.policy =~ "folder"
    assert checked.roles == ["user"]
    assert checked.principal == %{"clearance" => "cleared"}
    assert checked.resource == %{"member_roles" => ["reader"]}
    assert Line.key(checked) == {"an-account", "read", "folder", "1"}

    assert planned.number == 2
    assert planned.id == nil
    assert planned.verdict == :scoped
    assert Line.key(planned) == {"an-account", "read", "folder", nil}

    agreeing = [decision(:allow, {:folder, 1}, :read), decision(:scoped, {:folder, nil}, :read)]
    assert Decisions.reconcile(sidecar.audit_log, agreeing) == {:ok, []}

    drifted = [decision(:deny, {:folder, 1}, :read), decision(:scoped, {:folder, nil}, :read)]
    assert {:ok, [%Finding{} = finding]} = Decisions.reconcile(sidecar.audit_log, drifted)
    assert finding.kind == :verdict
    assert finding.subject == "an-account"
    assert finding.operation == "read"
    assert finding.object == {"folder", "1"}
    assert finding.line == 1
    assert finding.logged == :allow
    assert finding.recorded == :deny
    assert finding.policy == checked.policy
    assert Finding.describe(finding) =~ "verdict: an-account read folder 1"
    assert Finding.describe(finding) =~ "at line 1"
  end

  test "a line no record carries is unrecorded, and a record no line carries is unlogged" do
    path = log!([checked("ann", "read", "folder", "1", "EFFECT_ALLOW")])

    assert {:ok, [%Finding{kind: :unrecorded} = unrecorded]} = Decisions.reconcile(path, [])
    assert unrecorded.logged == :allow
    assert unrecorded.recorded == nil
    assert unrecorded.decision == nil

    recorded = decision(:allow, {:item, 7}, :edit)
    assert {:ok, findings} = Decisions.reconcile(path, [recorded])
    assert [%Finding{kind: :unrecorded}, %Finding{kind: :unlogged} = unlogged] = findings
    assert unlogged.subject == "an-account"
    assert unlogged.operation == "edit"
    assert unlogged.object == {"item", "7"}
    assert unlogged.line == nil
    assert unlogged.logged == nil
    assert unlogged.recorded == :allow
    assert unlogged.decision == recorded.id
  end

  test "the same question asked twice takes one record for each line" do
    path =
      log!([
        checked("an-account", "read", "folder", "1", "EFFECT_ALLOW"),
        checked("an-account", "read", "folder", "1", "EFFECT_DENY")
      ])

    both = [decision(:allow, {:folder, 1}, :read), decision(:deny, {:folder, 1}, :read)]
    assert Decisions.reconcile(path, both) == {:ok, []}

    assert {:ok, [%Finding{line: 2, logged: :deny, recorded: :allow}]} =
             Decisions.reconcile(path, [decision(:allow, {:folder, 1}, :read), decision(:allow, {:folder, 1}, :read)])
  end

  test "a plan that admits no row is a denial, and a line that is no decision carries nothing" do
    path = log!([planned("ann", "read", "folder", %{"kind" => "KIND_ALWAYS_DENIED"}), %{"callId" => "none"}])

    assert {:ok, [%Line{} = line]} = Decisions.lines(path)
    assert line.verdict == :deny
    assert line.policy == nil
    assert line.resource == %{}
    assert line.roles == ["user"]
  end

  test "an output the log carries with no input of its own answers about no resource" do
    output = %{"requestId" => "unmatched", "actions" => %{"read" => %{"effect" => "EFFECT_DENY"}}}
    path = log!([%{"checkResources" => %{"inputs" => [], "outputs" => [output]}}])

    assert {:ok, [%Line{} = line]} = Decisions.lines(path)
    assert line.subject == nil
    assert line.kind == nil
    assert line.verdict == :deny
    assert line.roles == []
    assert line.principal == %{}
  end

  test "a line that is no JSON object is a log this module refuses to read" do
    path = Path.join(directory!(), "broken.log")
    File.write!(path, JSON.encode!(%{"callId" => "one"}) <> "\nnot json at all\n")

    assert {:error, %Error.Invalid{what: :decision_log} = error} = Decisions.lines(path)
    assert error.detail =~ "line 2 of #{path} is no JSON object"
  end

  test "a log that is not there is an error naming the path" do
    path = Path.join(directory!(), "absent.log")

    assert {:error, %Error.Invalid{what: :decision_log} = error} = Decisions.reconcile(path, [])
    assert error.detail =~ "cannot read the decision log at #{path}"
    assert error.detail =~ "no such file or directory"
  end

  test "the kinds a finding takes are the three differences reconciliation reports" do
    assert Finding.kinds() == [:unrecorded, :unlogged, :verdict]
    assert Finding.reference({:folder, nil}) == {"folder", nil}
    assert Finding.reference({:folder, 1}) == {"folder", "1"}

    scope = %Finding{
      kind: :unrecorded,
      subject: "ann",
      operation: "read",
      object: {"folder", nil},
      line: nil,
      logged: :scoped,
      recorded: nil
    }

    assert Finding.describe(scope) == "unrecorded: ann read every folder logged :scoped, recorded nil"
  end

  defp two(path) do
    case Decisions.lines(path) do
      {:ok, [_check, _plan] = lines} -> lines
      _not_yet -> false
    end
  end

  defp plan_body do
    Request.plan(%Subject{id: "an-account", kind: :user}, :read, :folder, %{"clearance" => "cleared"})
  end

  defp checked(subject, action, kind, id, effect) do
    %{
      "checkResources" => %{
        "inputs" => [
          %{
            "requestId" => id,
            "principal" => %{"id" => subject, "roles" => ["user"], "attr" => %{"clearance" => "cleared"}},
            "resource" => %{"kind" => kind, "id" => id, "attr" => %{"member_roles" => ["reader"]}},
            "actions" => [action]
          }
        ],
        "outputs" => [
          %{
            "requestId" => id,
            "resourceId" => id,
            "actions" => %{action => %{"effect" => effect, "policy" => "NO_MATCH"}}
          }
        ]
      }
    }
  end

  defp planned(subject, action, kind, filter) do
    %{
      "planResources" => %{
        "input" => %{
          "principal" => %{"id" => subject, "roles" => ["user"], "attr" => %{}},
          "resource" => %{"kind" => kind},
          "action" => action
        },
        "output" => %{"action" => action, "kind" => kind, "filter" => filter}
      }
    }
  end

  defp log!(entries) do
    path = Path.join(directory!(), "decisions.log")
    File.write!(path, Enum.map_join(entries, "", &(JSON.encode!(&1) <> "\n")))
    path
  end

  defp directory! do
    directory = Path.join([File.cwd!(), "tmp", "decisions-#{System.unique_integer([:positive])}"])
    File.mkdir_p!(directory)
    on_exit(fn -> File.rm_rf!(directory) end)
    directory
  end

  defp decision(verdict, object, operation) do
    %Decision{
      id: Id.new(),
      subject: %Subject{id: "an-account", kind: :user},
      object: object,
      operation: operation,
      verdict: verdict,
      reason: Reason.deny_by_default(),
      adapter: Turnstile.Cerbos,
      policy_version: "conformance",
      head_position: nil,
      applied_position: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }
  end
end
