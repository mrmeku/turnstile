defmodule Example.Scenarios.Table do
  @moduledoc """
  The scenario table of `docs/example.md` §4 as the committed list. The
  freeze test holds it to the document; the `scenario` macro validates every
  declaration against it; the count test reads its size. Changing a row
  means changing the document first, in its own commit, then this list.

  `tests` names the rules, `:c1` to `:c13`, or `:review` for the scenario
  that shows the port's review verb.
  """

  alias Example.Scenarios.Row

  @rows [
    {"enf-01", "A User with an Assignment to a Document's Program reads it", :enforcement, ~w[AC-3], [:c1]},
    {"enf-02", "A User with neither an Assignment nor an OfficeRole is denied the Document", :enforcement, ~w[AC-3],
     [:c1]},
    {"enf-03",
     "A User holding an OfficeRole in the designating Office reads a Document of that Office's Program without an Assignment",
     :enforcement, ~w[AC-3], [:c1]},
    {"enf-04", "A contractor is denied a FED ONLY Document they are assigned to", :enforcement, ~w[AC-3 AC-16*], [:c2]},
    {"enf-05", "A foreign national is denied a NOFORN Document of a domestic Agency", :enforcement, ~w[AC-3], [:c2]},
    {"enf-06", "A User whose nationality is outside the REL TO list is denied the Document", :enforcement, ~w[AC-3],
     [:c2]},
    {"enf-07", "A User on the DL ONLY list reads the Document and one not on it is denied", :enforcement, ~w[AC-3],
     [:c2, :c6]},
    {"enf-08", "A Document carrying two controls is denied to a User who clears one of them", :enforcement, ~w[AC-3],
     [:c2]},
    {"enf-09", "A Specified category's implied control blocks a User the declared controls would allow", :enforcement,
     ~w[AC-3], [:c3]},
    {"enf-10", "A Document with no controls is read by any User with a lawful purpose", :enforcement, ~w[AC-3], [:c2]},
    {"enf-11",
     "A NOFORN Portion is removed from a foreign national's redacted read while the rest of the Document returns",
     :enforcement, ~w[AC-3], [:c4, :c13]},
    {"enf-12", "A Document marking that would drop a Portion's control is refused at write time", :enforcement,
     ~w[AC-3 AC-16*], [:c4]},
    {"enf-13", "After the decontrol date a contractor reads a FED ONLY Document they are assigned to", :enforcement,
     ~w[AC-3], [:c5]},
    {"enf-14", "Before the decontrol date, by the port's clock, the same Document is denied", :enforcement, ~w[AC-3],
     [:c5]},
    {"enf-15", "A decontrolled Document is still denied to a User with no lawful purpose", :enforcement, ~w[AC-3],
     [:c5, :c1]},
    {"enf-16", "DL ONLY membership without an Assignment does not grant the read", :enforcement, ~w[AC-3], [:c6]},
    {"enf-17", "A Document of another Agency is neither returned by `scope` nor readable by `check`", :enforcement,
     ~w[AC-3], [:c1, :c13]},
    {"enf-18", "A User one Portion releases to and another does not is denied the whole Document", :enforcement,
     ~w[AC-3 AC-16*], [:c4, :c2]},
    {"lp-01", "A Program member without an OfficeRole cannot change a Document's marking", :least_privilege,
     ~w[AC-6 AC-6(1)], [:c7]},
    {"lp-02", "A designator of another Office cannot change the marking", :least_privilege, ~w[AC-6(1)], [:c7]},
    {"lp-03", "A designator of the designating Office changes the marking", :least_privilege, ~w[AC-6(1)], [:c7]},
    {"lp-04", "Setting a decontrol needs a designator", :least_privilege, ~w[AC-6(1)], [:c7]},
    {"lp-05", "A Portion's marking change needs a designator of the Document's designating Office", :least_privilege,
     ~w[AC-6(1)], [:c7, :c4]},
    {"lp-06", "An ordinary account cannot invoke the override", :least_privilege, ~w[AC-6(10)], [:c10]},
    {"lp-07", "A privileged account is a separate account: the same person's ordinary account cannot override",
     :least_privilege, ~w[AC-6(2)], [:c10]},
    {"lp-08", "The access review lists every privileged account and every permission a role holds", :least_privilege,
     ~w[AC-6(5) AC-2(7)], [:c7, :c10]},
    {"sod-01", "A marking change proposed by a designator is approved by a different approver", :separation_of_duties,
     ~w[AC-5], [:c9]},
    {"sod-02", "The proposer, who is also an approver, cannot approve their own proposal", :separation_of_duties,
     ~w[AC-5], [:c9]},
    {"sod-03", "A proposal without approval does not change the marking", :separation_of_duties, ~w[AC-5 CM-5], [:c9]},
    {"rev-01",
     "A revoked Assignment denies the next check; the measured latency and its components are recorded, never asserted",
     :revocation_and_expiry, ~w[AC-2 PS-4 AC-3(8)*], [:c11, :c12]},
    {"rev-02", "Removal from a DL ONLY list denies the next read", :revocation_and_expiry, ~w[AC-2 AC-2(1)], [:c11]},
    {"rev-03", "A change of employment from federal to contractor denies a FED ONLY read at the next check",
     :revocation_and_expiry, ~w[AC-2 PS-5], [:c11]},
    {"rev-04", "A corrected nationality applies at the next check", :revocation_and_expiry, ~w[AC-2 AC-16*], [:c11]},
    {"rev-05", "A closed Program revokes every Assignment's lawful purpose at the next check", :revocation_and_expiry,
     ~w[AC-2 AC-2(3)], [:c11]},
    {"rev-06",
     "A revocation deletes nothing but the fact: the Document and the Program remain, and the grant and the revoke are both evented",
     :revocation_and_expiry, ~w[AC-2(4)], [:c11]},
    {"rvw-01", "The access review lists who can read what today, per Agency", :access_review, ~w[AC-2 AC-6(7)],
     [:review]},
    {"ia-01", "A designator whose session re-authenticated within the window changes a marking", :re_authentication,
     ~w[IA-11], [:c8]},
    {"ia-02", "A designator whose session is older than the window is refused until re-authentication",
     :re_authentication, ~w[IA-11], [:c8]},
    {"ia-03", "A marking change with no re-authentication fact supplied is denied", :re_authentication, ~w[IA-11], [:c8]},
    {"ovr-01",
     "A privileged user with the override permission reads outside C1 with a justification, and the read emits its own event and is reported to the designating Office",
     :emergency_override, ~w[AC-6(9) AU-6], [:c10]},
    {"ovr-02", "Without a justification the override is denied", :emergency_override, ~w[AC-6(9)], [:c10]},
    {"ovr-03", "The override never reaches C7: a privileged user cannot change a marking through it", :emergency_override,
     ~w[AC-6(9) AC-6(1)], [:c10, :c7]}
  ]

  @scenarios Enum.map(@rows, fn {id, sentence, group, controls, tests} ->
               %Row{id: id, sentence: sentence, group: group, controls: controls, tests: tests}
             end)

  @doc "Every scenario, in the table's order."
  @spec all() :: [Row.t()]
  def all, do: @scenarios

  @doc "The ids, in the table's order."
  @spec ids() :: [String.t()]
  def ids, do: Enum.map(@scenarios, & &1.id)

  @doc "The scenario with an id."
  @spec fetch(String.t()) :: {:ok, Row.t()} | :error
  def fetch(id) when is_binary(id) do
    case Enum.find(@scenarios, &(&1.id == id)) do
      nil -> :error
      %Row{} = scenario -> {:ok, scenario}
    end
  end

  @doc "How many scenarios a thin application runs: the rows."
  @spec count() :: non_neg_integer()
  def count, do: length(@scenarios)
end
