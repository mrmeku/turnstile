defmodule Turnstile.Conformance.Law do
  @moduledoc """
  The law table of `docs/conformance.md` §2 as data: one row per
  requirement line, named by its id and its sentence and citing the
  controls it answers. `Turnstile.Conformance.AdapterCase` names each test
  it defines from a row here, and the freeze test in `turnstile` holds the
  table to the document row for row, so the suite and the document cannot
  drift apart without a commit that changes both.

  The bodies are in `Turnstile.Conformance.AdapterCase.Laws` and its
  modules. A row whose body the template does not yet carry is still a row
  here, since the document lists it, and the freeze test is what says the
  two agree.
  """

  @laws [
    {"ac2-01",
     "A single-row insert, update, or delete of an account through the seam emits one change event naming " <>
       "the deciding subject, the target, and the clearance before and after", ["AC-2", "AC-2(4)"]},
    {"ac2-02",
     "A grant that expires one second after the port's clock allows and one that expired one second before " <>
       "denies, by the configured clock and not the database's", ["AC-2(2)", "AC-2(3)"]},
    {"ac2-03", "A subject whose account no longer satisfies the rule is denied at the next check with no other change",
     ["AC-2(3)", "PS-5"]},
    {"ac2-04",
     "Review returns, for every subject including a privileged one, a rule that lists exactly the objects check " <>
       "allows, with one decision per subject and one for the reviewer under one operation id", ["AC-2(7)", "AC-6(7)"]},
    {"ac2-05",
     "After a grant is revoked the next check denies, and the latency from revocation to denial is printed and " <>
       "never asserted", ["AC-2(13)", "PS-4"]},
    {"ac3-01", "check agrees with the world's own rule for every subject, operation, and object drawn", ["AC-3"]},
    {"ac3-02",
     "An ungranted object, an unknown operation, an unknown subject, and an unknown subject kind are denied, " <>
       "the last before the adapter is called", ["AC-3"]},
    {"ac3-03",
     "scope returns exactly the rows check allows, for the scoped schema and for the schema its decision carries",
     ["AC-3"]},
    {"ac3-04", "scope over a thousand rows is one decision and one query beyond setup", ["AC-3"]},
    {"ac3-05", "An unreachable decider denies and emits one decision event carrying the exception", ["AC-3"]},
    {"ac6-01",
     "A user holding a grant is allowed, and the privileged subject of the same account is denied the same object",
     ["AC-6(2)"]},
    {"au2-01",
     "Every authorize and check emits exactly one decision event carrying subject, kind, operation, object, " <>
       "verdict, reason, version, operation id, and time", ["AU-2", "AC-6(9)"]},
    {"au2-02", "A denial's decision event carries the reason for it", ["AU-2"]},
    {"au2-03", "scope and review emit decisions whose verdict is scoped", ["AU-2"]},
    {"au3-01", "No value in a decision event equals an attribute value of the world", ["AU-3"]},
    {"au3-02",
     "A change event carries operation, kind, target, actor, time, operation id, and the old and new value of " <>
       "every fact column that changed", ["AU-3"]},
    {"au3-03", "An access event carries object type, ids, decision id, subject, operation id, and time", ["AU-3"]},
    {"au3-04", "Within one operation id the decision, change, and access events each carry it", ["AU-3(1)"]},
    {"au12-01", "A single-row write to an audited schema emits its change event inside the write's transaction",
     ["AU-12", "AC-2(4)"]},
    {"au12-02", "A bulk write to an audited schema raises and changes nothing", ["AU-12"]},
    {"au12-03", "A write that goes around the seam emits nothing", ["AU-12"]},
    {"au12-04", "A write the database refuses leaves no row and no event", ["AU-12"]},
    {"au12-05", "An unmediated read or write of a protected schema is refused", ["AU-12"]},
    {"au12-06", "Every mediated read of a protected schema emits one access event", ["AU-12"]},
    {"cm3-01", "Publishing a version emits the adapter's version event naming the author and the approval",
     ["CM-3", "CM-5"]},
    {"cm3-02", "A decision reports the version it was taken under, before and after a new version is published",
     ["CM-3(2)"]},
    {"cm3-03", "A tightened rule is a policy version whose event names the artifact it is on this adapter", ["CM-5(1)"]},
    {"cm3-04",
     "After a rule is tightened the reader it excludes is denied, and the propagation latency is printed and " <>
       "never asserted", ["CM-3(2)"]}
  ]

  @enforce_keys [:id, :sentence, :controls]
  defstruct @enforce_keys

  @type t :: %__MODULE__{id: String.t(), sentence: String.t(), controls: [String.t()]}

  @doc "Every law, in the order of the document."
  @spec all() :: [t()]
  def all,
    do: Enum.map(@laws, fn {id, sentence, controls} -> %__MODULE__{id: id, sentence: sentence, controls: controls} end)

  @doc "The law ids, in the order of the document."
  @spec ids() :: [String.t()]
  def ids, do: Enum.map(@laws, &elem(&1, 0))

  @doc "The law with this id; raises for an id the table does not hold."
  @spec fetch!(String.t()) :: t()
  def fetch!(id) when is_binary(id) do
    Enum.find(all(), &(&1.id == id)) || raise ArgumentError, "no law #{id} in Turnstile.Conformance.Law"
  end

  @doc "The test name of a law: its id and its sentence."
  @spec name(String.t()) :: String.t()
  def name(id) when is_binary(id) do
    law = fetch!(id)
    "#{law.id} #{law.sentence}"
  end
end
