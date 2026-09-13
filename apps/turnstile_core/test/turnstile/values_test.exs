defmodule Turnstile.ValuesTest do
  use ExUnit.Case, async: true

  alias Turnstile.Answer
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.Port
  alias Turnstile.Projection.Drift

  test "ids are UUIDs" do
    id = Id.new()
    assert Id.valid?(id)
    refute Id.valid?("not an id")
    refute Id.valid?(:not_a_string)
  end

  test "subjects have refs and kinds" do
    id = Id.new()
    assert FactEvent.subject_ref({:privileged, id}) == {:user, id}
    assert Port.subject_kinds() == [:user, :non_person_entity, :privileged]
    assert %Environment{now: ~U[2026-09-08 00:00:00Z], facts: %{}} = %Environment{now: ~U[2026-09-08 00:00:00Z]}
  end

  test "an answer carries a verdict, a reason, a version, and the decider's own meta" do
    assert %Answer{version: nil, meta: %{}} = %Answer{verdict: :deny, reason: :deny_by_default}
    assert %Answer{meta: %{rule: "r"}} = %Answer{verdict: :allow, reason: :allowed, version: "v", meta: %{rule: "r"}}

    assert Answer.reasons() ==
             ~w(allowed deny_by_default rule_denied engine_unreachable missing_fact unknown_operation
                unknown_subject_kind)a
  end

  test "errors have messages" do
    assert Exception.message(%Error.Unmediated{function: :all, arity: 2, schema: nil}) =~ "Repo.all/2 carries no decision"
    assert Exception.message(%Error.Unmediated{function: :all, arity: 2, schema: Enum}) =~ "on Enum"
    assert Exception.message(%Error.Engine{adapter: Enum, operation: :check, detail: "x"}) =~ "failed during check"
    assert Exception.message(%Error.Invalid{what: :config, detail: "x"}) == "invalid config: x"

    subject = {:user, Id.new()}

    assert Exception.message(%Error.NotAuthorized{
             subject: subject,
             operation: :read,
             object: {:thing, "1"},
             reason: :deny_by_default
           }) =~ "may not read"

    assert Exception.message(%Error.NotAuthorized{
             subject: subject,
             operation: :read,
             object: {:thing, "1"},
             reason: :engine_unreachable,
             detail: "down"
           }) =~ "engine_unreachable (down)"
  end

  test "drift is clean when nothing is missing or extra" do
    assert Drift.clean?(%Drift{missing: [], extra: [], checked_to: 0})
    refute Drift.clean?(%Drift{missing: [{:user, "1"}], extra: [], checked_to: 0})
  end
end
