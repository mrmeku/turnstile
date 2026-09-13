defmodule Turnstile.Conformance.CaseTest do
  use Turnstile.Conformance.Case, capabilities: Turnstile.Test.Capabilities, async: true

  alias Turnstile.Conformance.Case
  alias Turnstile.Conformance.Scenario
  alias Turnstile.Conformance.Scenarios
  alias Turnstile.Test.Capabilities

  scenario "enf-01", "A User with an Assignment to a Document's Program reads it", control: ["AC-3"], rule: :c1 do
    assert true
  end

  # Skipped through the declaration's `unsupported` record; the skip reason is the note.
  scenario "enf-09", "A Specified category's implied control blocks a User the declared controls would allow",
    control: ["AC-3"],
    rule: :c3 do
    flunk("an unsupported scenario never runs")
  end

  scenario "rev-07", "A revocation deletes nothing but the fact: the Document, the Program, and the history remain",
    control: ["AC-2(4)"],
    rule: :c11 do
    assert true
  end

  test "the macro names the test by id and sentence and tags it" do
    tags = __MODULE__.__info__(:attributes)
    assert is_list(tags)

    assert Case.__tags__(
             "enf-01",
             "A User with an Assignment to a Document's Program reads it",
             [control: ["AC-3"], rule: :c1],
             Capabilities
           ) ==
             [
               scenario: "enf-01",
               rule: :c1,
               controls: ["AC-3"],
               capability: {:native, by: :adapter, note: "the test declaration"}
             ]

    assert Case.__name__("enf-01", "sentence") == "enf-01 sentence"
  end

  test "an unsupported rule adds a skip tag with the note, and a ledger scenario its needs_ledger tag" do
    tags =
      Case.__tags__(
        "enf-09",
        "A Specified category's implied control blocks a User the declared controls would allow",
        [control: ["AC-3"], rule: :c3],
        Capabilities
      )

    assert tags[:skip] == "the test declaration marks C3 unsupported"

    tags =
      Case.__tags__(
        "rev-07",
        "A revocation deletes nothing but the fact: the Document, the Program, and the history remain",
        [control: ["AC-2(4)"], rule: :c11],
        Capabilities
      )

    assert tags[:needs_ledger] == true
    refute Keyword.has_key?(tags, :skip)
  end

  test "a declaration that drifts from the table is refused" do
    sentence = "A User with an Assignment to a Document's Program reads it"

    assert_raise ArgumentError, ~r/no scenario "enf-99"/, fn ->
      Case.__tags__("enf-99", sentence, [control: ["AC-3"], rule: :c1], Capabilities)
    end

    assert_raise ArgumentError, ~r/reads/, fn ->
      Case.__tags__("enf-01", "another sentence", [control: ["AC-3"], rule: :c1], Capabilities)
    end

    assert_raise ArgumentError, ~r/tests \[:c1\]/, fn ->
      Case.__tags__("enf-01", sentence, [control: ["AC-3"], rule: :c2], Capabilities)
    end

    assert_raise ArgumentError, ~r/cites/, fn ->
      Case.__tags__("enf-01", sentence, [control: ["AC-6"], rule: :c1], Capabilities)
    end
  end

  test "the table answers fetch, ids, and the expected count per ledger mode" do
    assert {:ok, %Scenario{id: "enf-01", group: :enforcement}} = Scenarios.fetch("enf-01")
    assert :error = Scenarios.fetch("enf-99")
    assert length(Scenarios.ids()) == length(Scenarios.all())
    unsupported = Enum.count(Scenarios.all(), &Scenarios.unsupported?(Capabilities, &1))
    assert unsupported == 1
    ledger_only = Enum.count(Scenarios.all(), & &1.needs_ledger)
    assert Scenarios.expected_count(Capabilities, :ecto) == length(Scenarios.all()) - unsupported
    assert Scenarios.expected_count(Capabilities, :none) == length(Scenarios.all()) - unsupported - ledger_only
    assert Turnstile.Capabilities.levels() == [:native, :limited, :unsupported]
    assert Turnstile.Capabilities.components() == [:adapter, :seam, :database, :engine, :application]
  end
end
