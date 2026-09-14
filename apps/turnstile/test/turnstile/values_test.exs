defmodule Turnstile.ValuesTest do
  use ExUnit.Case, async: true

  alias Turnstile.Answer
  alias Turnstile.Error
  alias Turnstile.Id
  alias Turnstile.Port

  test "ids are UUIDs" do
    id = Id.new()
    assert Id.valid?(id)
    refute Id.valid?("not an id")
    refute Id.valid?(:not_a_string)
  end

  test "the port knows three subject kinds" do
    assert Port.subject_kinds() == [:user, :non_person_entity, :privileged]
  end

  test "an answer carries a verdict, a reason, a version, and the decider's own meta" do
    assert %Answer{version: nil, meta: %{}} = %Answer{verdict: :deny, reason: :deny_by_default}
    assert %Answer{meta: %{rule: "r"}} = %Answer{verdict: :allow, reason: :allowed, version: "v", meta: %{rule: "r"}}

    assert Answer.reasons() ==
             ~w(allowed deny_by_default rule_denied engine_unreachable missing_fact unknown_operation
                unknown_subject_kind)a
  end

  test "an error is a reason and a detail, and the detail is the message" do
    assert Error.reasons() ==
             ~w(deny_by_default rule_denied engine_unreachable missing_fact unknown_operation unknown_subject_kind
                unsupported invalid unmediated)a

    assert Exception.message(%Error{reason: :engine_unreachable, detail: "x failed"}) == "x failed"
    assert Exception.message(Error.invalid(:config, "x")) == "invalid config: x"

    subject = {:user, Id.new()}

    assert Exception.message(Error.denied(subject, :read, {:thing, "1"}, :deny_by_default)) =~ "may not read"

    assert Exception.message(Error.denied(subject, :read, {:thing, "1"}, :engine_unreachable, "down")) =~
             "engine_unreachable (down)"
  end
end
