defmodule Turnstile.ValuesTest do
  use ExUnit.Case, async: true

  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Id
  alias Turnstile.Object
  alias Turnstile.Projection.Drift
  alias Turnstile.Reason
  alias Turnstile.Subject

  test "ids are UUIDs" do
    id = Id.new()
    assert Id.valid?(id)
    refute Id.valid?("not an id")
    refute Id.valid?(:not_a_string)
  end

  test "subjects and objects have refs and kinds" do
    id = Id.new()
    assert Subject.ref(%Subject{id: id, kind: :user}) == {:user, id}
    assert Subject.kinds() == [:user, :non_person_entity, :privileged]
    assert Object.ref(%Object{type: :thing, id: id}) == {:thing, id}
    assert %Environment{now: ~U[2026-09-08 00:00:00Z], facts: %{}} = %Environment{now: ~U[2026-09-08 00:00:00Z]}
  end

  test "reasons carry a code, a message, and the rule where one applies" do
    assert %Reason{code: :allowed, rule: "r"} = Reason.allowed("r")
    assert %Reason{code: :allowed, rule: nil} = Reason.allowed()
    assert %Reason{code: :deny_by_default} = Reason.deny_by_default()
    assert %Reason{code: :rule_denied, rule: "r"} = Reason.rule_denied("r")
    assert %Reason{code: :engine_unreachable, message: message} = Reason.engine_unreachable("down")
    assert message =~ "down"
    assert %Reason{code: :missing_fact, message: message} = Reason.missing_fact(:nationality)
    assert message =~ "nationality"
  end

  test "errors have messages" do
    assert Exception.message(%Error.Unmediated{function: :all, arity: 2, schema: nil}) =~ "Repo.all/2 carries no decision"
    assert Exception.message(%Error.Unmediated{function: :all, arity: 2, schema: Enum}) =~ "on Enum"
    assert Exception.message(%Error.Engine{adapter: Enum, operation: :check, detail: "x"}) =~ "failed during check"
    assert Exception.message(%Error.Invalid{what: :config, detail: "x"}) == "invalid config: x"

    subject = %Subject{id: Id.new(), kind: :user}

    assert Exception.message(%Error.NotAuthorized{
             subject: subject,
             operation: :read,
             object: {:thing, "1"},
             reason: Reason.deny_by_default()
           }) =~ "may not read"
  end

  test "drift is clean when nothing is missing or extra" do
    assert Drift.clean?(%Drift{missing: [], extra: [], checked_to: 0})
    refute Drift.clean?(%Drift{missing: [{:user, "1"}], extra: [], checked_to: 0})
  end

  test "the system clock answers UTC" do
    assert %DateTime{time_zone: "Etc/UTC"} = Turnstile.Clock.System.now()
  end
end
