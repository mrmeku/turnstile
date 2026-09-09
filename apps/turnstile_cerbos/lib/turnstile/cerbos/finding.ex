defmodule Turnstile.Cerbos.Finding do
  @moduledoc """
  A difference between what the sidecar wrote in its decision log and what
  the port recorded: a decision the log carries that no record matches, a
  record no line of the log carries, or a pair that match on who asked what
  and disagree on the answer.

  A finding is not an error. It is the thing a reviewer reads, so it names
  the line, the question, and both verdicts where there are two.
  """

  alias Turnstile.Decision
  alias Turnstile.Object

  @kinds [:unrecorded, :unlogged, :verdict]

  @enforce_keys [:kind, :subject, :operation, :object, :line, :logged, :recorded]
  defstruct [:kind, :subject, :operation, :object, :line, :logged, :recorded, decision: nil, policy: nil]

  @typedoc "A decision the record does not carry, a record the log does not carry, or a disagreement."
  @type kind :: :unrecorded | :unlogged | :verdict

  @type t :: %__MODULE__{
          kind: kind(),
          subject: String.t(),
          operation: String.t(),
          object: {String.t(), String.t() | nil},
          line: pos_integer() | nil,
          logged: Decision.verdict() | nil,
          recorded: Decision.verdict() | nil,
          decision: Turnstile.Id.t() | nil,
          policy: String.t() | nil
        }

  @doc "The kinds, in the order the type lists them."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc "A finding as one sentence, for a report a person reads."
  @spec describe(t()) :: String.t()
  def describe(%__MODULE__{} = finding) do
    "#{finding.kind}: #{finding.subject} #{finding.operation} #{object(finding.object)}" <>
      " logged #{inspect(finding.logged)}, recorded #{inspect(finding.recorded)}" <>
      line(finding.line)
  end

  @doc "The reference of a decision's object as a finding names it: both parts as text, the id absent for a scope."
  @spec reference(Object.ref()) :: {String.t(), String.t() | nil}
  def reference({type, nil}), do: {to_string(type), nil}
  def reference({type, id}), do: {to_string(type), to_string(id)}

  defp object({kind, nil}), do: "every #{kind}"
  defp object({kind, id}), do: "#{kind} #{id}"

  defp line(nil), do: ""
  defp line(number), do: " at line #{number}"
end
