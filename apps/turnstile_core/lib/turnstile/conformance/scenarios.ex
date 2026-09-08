defmodule Turnstile.Conformance.Scenarios do
  @moduledoc """
  The scenario table of the reference's §3a as the committed list. The
  freeze test holds it to the document; the `scenario` macro validates every
  declaration against it; the count test reads its size. Changing a row
  means changing the reference first, in its own commit, then this list.

  `tests` names the rules, `:c1` to `:c13`, or the guarantee a scenario
  tests in the domain's words.
  """

  alias Turnstile.Conformance.Scenario

  @rows [
    {"enf-01", "A User with an Assignment to a Document's Program reads it", :enforcement, ~w[AC-3], [:c1], false},
    {"enf-02", "A User with neither an Assignment nor an OfficeRole is denied the Document", :enforcement, ~w[AC-3],
     [:c1], false},
    {"enf-03",
     "A User holding an OfficeRole in the designating Office reads a Document of that Office's Program without an Assignment",
     :enforcement, ~w[AC-3], [:c1], false},
    {"enf-04", "A contractor is denied a FED ONLY Document they are assigned to", :enforcement, ~w[AC-3 AC-16*], [:c2],
     false},
    {"enf-05", "A foreign national is denied a NOFORN Document of a domestic Agency", :enforcement, ~w[AC-3], [:c2],
     false},
    {"enf-06", "A User whose nationality is outside the REL TO list is denied the Document", :enforcement, ~w[AC-3],
     [:c2], false},
    {"enf-07", "A User on the DL ONLY list reads the Document and one not on it is denied", :enforcement, ~w[AC-3],
     [:c2, :c6], false},
    {"enf-08", "A Document carrying two controls is denied to a User who clears one of them", :enforcement, ~w[AC-3],
     [:c2], false},
    {"enf-09", "A Specified category's implied control blocks a User the declared controls would allow", :enforcement,
     ~w[AC-3], [:c3], false},
    {"enf-10", "A Document with no controls is read by any User with a lawful purpose", :enforcement, ~w[AC-3], [:c2],
     false},
    {"enf-11",
     "A NOFORN Portion is removed from a foreign national's redacted read while the rest of the Document returns",
     :enforcement, ~w[AC-3], [:c4, :c13], false},
    {"enf-12", "A Document marking that would drop a Portion's control is refused at write time", :enforcement,
     ~w[AC-3 AC-16*], [:c4], false},
    {"enf-13", "After the decontrol date a contractor reads a FED ONLY Document they are assigned to", :enforcement,
     ~w[AC-3], [:c5], false},
    {"enf-14", "Before the decontrol date, by the port's clock, the same Document is denied", :enforcement, ~w[AC-3],
     [:c5], false},
    {"enf-15", "A decontrolled Document is still denied to a User with no lawful purpose", :enforcement, ~w[AC-3],
     [:c5, :c1], false},
    {"enf-16", "DL ONLY membership without an Assignment does not grant the read", :enforcement, ~w[AC-3], [:c6], false},
    {"enf-17", "The Documents `scope` returns are exactly the Documents `check` allows, over random subjects",
     :enforcement, ~w[AC-3 AC-25*], [:c13], false},
    {"enf-18", "The Portions `scope` returns are exactly the Portions `check` allows", :enforcement, ~w[AC-3], [:c13],
     false},
    {"enf-19", "A Document of another Agency is neither returned by `scope` nor readable by `check`", :enforcement,
     ~w[AC-3], [:c1, :c13], false},
    {"lp-01", "A Program member without an OfficeRole cannot change a Document's marking", :least_privilege,
     ~w[AC-6 AC-6(1)], [:c7], false},
    {"lp-02", "A designator of another Office cannot change the marking", :least_privilege, ~w[AC-6(1)], [:c7], false},
    {"lp-03", "A designator of the designating Office changes the marking", :least_privilege, ~w[AC-6(1)], [:c7], false},
    {"lp-04", "Setting a decontrol needs a designator", :least_privilege, ~w[AC-6(1)], [:c7], false},
    {"lp-05", "A Portion's marking change needs a designator of the Document's designating Office", :least_privilege,
     ~w[AC-6(1)], [:c7, :c4], false},
    {"lp-06", "An ordinary account cannot invoke the override", :least_privilege, ~w[AC-6(10)], [:c10], false},
    {"lp-07", "A privileged account is a separate account: the same person's ordinary account cannot override",
     :least_privilege, ~w[AC-6(2)], [:c10], false},
    {"lp-08", "`mix turnstile.review` lists every privileged account and every permission a role holds", :least_privilege,
     ~w[AC-6(5) AC-2(7)], [:c7, :c10], false},
    {"sod-01", "A marking change proposed by a designator is approved by a different approver", :separation_of_duties,
     ~w[AC-5], [:c9], false},
    {"sod-02", "The proposer, who is also an approver, cannot approve their own proposal", :separation_of_duties,
     ~w[AC-5], [:c9], false},
    {"sod-03", "A proposal without approval does not change the marking", :separation_of_duties, ~w[AC-5 CM-5], [:c9],
     false},
    {"rev-01",
     "A revoked Assignment denies the next check; the measured latency and its components are recorded, never asserted",
     :revocation_and_expiry, ~w[AC-2 PS-4 AC-3(8)*], [:c11, :c12], false},
    {"rev-02", "Removal from a DL ONLY list denies the next read", :revocation_and_expiry, ~w[AC-2 AC-2(1)], [:c11],
     false},
    {"rev-03", "A change of employment from federal to contractor denies a FED ONLY read at the next check",
     :revocation_and_expiry, ~w[AC-2 PS-5], [:c11], false},
    {"rev-04", "A corrected nationality applies at the next check", :revocation_and_expiry, ~w[AC-2 AC-16*], [:c11],
     false},
    {"rev-05", "A closed Program revokes every Assignment's lawful purpose at the next check", :revocation_and_expiry,
     ~w[AC-2 AC-2(3)], [:c11], false},
    {"rev-06",
     "A tightened rule, published as a policy version, is enforced within the measured propagation, which is recorded",
     :revocation_and_expiry, ~w[AC-2 CM-3], [:c12], false},
    {"rev-07", "A revocation deletes nothing but the fact: the Document, the Program, and the history remain",
     :revocation_and_expiry, ~w[AC-2(4)], [:c11], true},
    {"aud-01",
     "Every Document read emits one decision event carrying subject, object, operation, verdict, reason, policy version, and positions",
     :decision_audit, ~w[AU-2 AU-3 AU-12], [:every_call_is_evented], false},
    {"aud-02", "A denied read emits its event with the reason", :decision_audit, ~w[AU-2 AU-3], [:every_call_is_evented],
     false},
    {"aud-03", "A decision record carries no attribute value", :decision_audit, ~w[AU-3], [:record_shape], false},
    {"aud-04",
     "A marking change emits one decision event and one fact event per changed fact field in the same transaction",
     :decision_audit, ~w[AU-12 AC-2(4)], [:no_fact_without_an_entry], true},
    {"aud-05", "A bulk re-marking of N Documents emits one audit record and N fact events sharing an operation id",
     :decision_audit, ~w[AU-12 AC-2(4)], [:per_operation_never_per_row], true},
    {"aud-06", "An Assignment grant and its revoke each produce a fact event carrying old and new", :decision_audit,
     ~w[AC-2(4)], [:the_fact_mapping], true},
    {"aud-07", "The example store's chain verifies, and a rewritten record breaks every hash after it", :decision_audit,
     ~w[AU-9 AU-9(4)], [:the_chained_store], false},
    {"aud-08", "A rolled-back write leaves no fact event and no decision outcome but the exception span", :decision_audit,
     ~w[AU-2 AU-12], [:atomicity], true},
    {"rvw-01", "`mix turnstile.review` lists who can read what today, per Agency", :access_review, ~w[AC-2 AC-6(7)],
     [:review], false},
    {"rvw-02", "With a ledger, review on a past date equals the fold stopped there", :access_review, ~w[AC-2 AC-6(7)],
     [:replay], true},
    {"rvw-03", "Replay reproduces a recorded decision from its applied position and policy version", :access_review,
     ~w[AC-2 AC-6(7)], [:replay], true},
    {"rvw-04", "An Assignment inserted outside the seam is reported by reconcile within the interval", :access_review,
     ~w[AC-2 AC-2(4)], [:drift], true},
    {"ia-01", "A designator whose session re-authenticated within the window changes a marking", :re_authentication,
     ~w[IA-11], [:c8], false},
    {"ia-02", "A designator whose session is older than the window is refused until re-authentication",
     :re_authentication, ~w[IA-11], [:c8], false},
    {"ia-03", "A marking change with no re-authentication fact supplied is denied", :re_authentication, ~w[IA-11], [:c8],
     false},
    {"ovr-01",
     "A privileged user with the override permission reads outside C1 with a justification, and the read emits its own event and is reported to the designating Office",
     :emergency_override, ~w[AC-6(9) AU-6], [:c10], false},
    {"ovr-02", "Without a justification the override is denied", :emergency_override, ~w[AC-6(9)], [:c10], false},
    {"ovr-03", "The override never reaches C7: a privileged user cannot change a marking through it", :emergency_override,
     ~w[AC-6(9) AC-6(1)], [:c10, :c7], false},
    {"cm-01", "Every policy-version event names its author and its approval", :change_control_on_policy, ~w[CM-3 CM-5],
     [:policy_versions], true},
    {"cm-02", "A decision made under version N carries N after version N+1 is published", :change_control_on_policy,
     ~w[CM-3], [:policy_versions], true},
    {"cm-03", "A rule change is a policy version whose event names the artifact it is on this adapter",
     :change_control_on_policy, ~w[CM-3], [:policy_versions], false}
  ]

  @scenarios Enum.map(@rows, fn {id, sentence, group, controls, tests, needs_ledger} ->
               %Scenario{
                 id: id,
                 sentence: sentence,
                 group: group,
                 controls: controls,
                 tests: tests,
                 needs_ledger: needs_ledger
               }
             end)

  @doc "Every scenario, in the table's order."
  @spec all() :: [Scenario.t()]
  def all, do: @scenarios

  @doc "The ids, in the table's order."
  @spec ids() :: [String.t()]
  def ids, do: Enum.map(@scenarios, & &1.id)

  @doc "The scenario with an id."
  @spec fetch(String.t()) :: {:ok, Scenario.t()} | :error
  def fetch(id) when is_binary(id) do
    case Enum.find(@scenarios, &(&1.id == id)) do
      nil -> :error
      %Scenario{} = scenario -> {:ok, scenario}
    end
  end

  @doc """
  How many scenarios a thin application must run without a skip: the rows,
  minus those whose every rule the declaration marks `unsupported`, minus,
  in ledger mode none, those that need a ledger.
  """
  @spec expected_count(module(), :ecto | :none) :: non_neg_integer()
  def expected_count(capabilities, ledger_mode) when is_atom(capabilities) and ledger_mode in [:ecto, :none] do
    Enum.count(@scenarios, fn %Scenario{} = scenario ->
      runs_in_mode? = ledger_mode == :ecto or not scenario.needs_ledger
      runs_in_mode? and not unsupported?(capabilities, scenario)
    end)
  end

  @doc "Whether the declaration marks the scenario's rule `unsupported`, with the note when it does."
  @spec unsupported?(module(), Scenario.t()) :: boolean()
  def unsupported?(capabilities, %Scenario{} = scenario) when is_atom(capabilities) do
    match?({:unsupported, _by_and_note}, capability(capabilities, scenario))
  end

  @doc "The declaration's record for the scenario's first rule."
  @spec capability(module(), Scenario.t()) :: Turnstile.Capabilities.declaration()
  def capability(capabilities, %Scenario{tests: [rule | _rest]}) when is_atom(capabilities) do
    capabilities.capability(rule)
  end
end
