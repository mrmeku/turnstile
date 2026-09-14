defmodule Turnstile.Conformance.CaseTest do
  use Turnstile.Conformance.Case, async: true

  alias Turnstile.Conformance.Case
  alias Turnstile.Conformance.Scenario
  alias Turnstile.Conformance.Scenarios

  scenario "enf-01", "A User with an Assignment to a Document's Program reads it", rule: :c1 do
    assert true
  end

  scenario "enf-09", "A Specified category's implied control blocks a User the declared controls would allow",
    rule: :c3 do
    assert true
  end

  scenario "rev-07",
           "A revocation deletes nothing but the fact: the Document and the Program remain, and the grant and the revoke are both evented",
           rule: :c11 do
    assert true
  end

  test "the macro names the test by id and sentence, and tags it from the table" do
    assert Case.__tags__("enf-01", "A User with an Assignment to a Document's Program reads it", rule: :c1) ==
             [scenario: "enf-01", rule: :c1, controls: ["AC-3"]]

    assert Case.__name__("enf-01", "sentence") == "enf-01 sentence"
  end

  test "a scenario that tests more than one rule takes either of them" do
    sentence =
      "A NOFORN Portion is removed from a foreign national's redacted read while the rest of the Document returns"

    assert Case.__tags__(
             "enf-11",
             sentence,
             rule: :c13
           ) == [scenario: "enf-11", rule: :c13, controls: ["AC-3"]]
  end

  test "a declaration that drifts from the table is refused" do
    sentence = "A User with an Assignment to a Document's Program reads it"

    assert_raise ArgumentError, ~r/no scenario "enf-99"/, fn ->
      Case.__tags__("enf-99", sentence, rule: :c1)
    end

    assert_raise ArgumentError, ~r/reads/, fn ->
      Case.__tags__("enf-01", "another sentence", rule: :c1)
    end

    assert_raise ArgumentError, ~r/tests \[:c1\]/, fn ->
      Case.__tags__("enf-01", sentence, rule: :c2)
    end
  end

  test "the table answers fetch, ids, and the count" do
    assert {:ok, %Scenario{id: "enf-01", group: :enforcement}} = Scenarios.fetch("enf-01")
    assert :error = Scenarios.fetch("enf-99")
    assert length(Scenarios.ids()) == length(Scenarios.all())
    assert Scenarios.count() == length(Scenarios.all())
  end
end
