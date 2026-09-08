defmodule Turnstile.Reason do
  @moduledoc "Why the verdict is what it is, in a form a record can carry without attribute values."

  @enforce_keys [:code, :message]
  defstruct [:code, :message, rule: nil]

  @typedoc "The fixed set of reasons; `rule` on the struct names the rule or clause where the adapter knows it."
  @type code ::
          :allowed
          | :deny_by_default
          | :rule_denied
          | :engine_unreachable
          | :missing_fact
          | :unknown_operation
          | :unknown_subject_kind

  @type t :: %__MODULE__{code: code(), message: String.t(), rule: String.t() | nil}

  @doc "A rule allowed the operation."
  @spec allowed(String.t() | nil) :: t()
  def allowed(rule \\ nil), do: %__MODULE__{code: :allowed, message: "allowed", rule: rule}

  @doc "No rule allowed it."
  @spec deny_by_default() :: t()
  def deny_by_default, do: %__MODULE__{code: :deny_by_default, message: "no rule allows the operation"}

  @doc "A rule denied it."
  @spec rule_denied(String.t()) :: t()
  def rule_denied(rule) when is_binary(rule), do: %__MODULE__{code: :rule_denied, message: "denied by rule", rule: rule}

  @doc "The engine could not be reached; the port fails closed."
  @spec engine_unreachable(String.t()) :: t()
  def engine_unreachable(detail) when is_binary(detail) do
    %__MODULE__{code: :engine_unreachable, message: "engine unreachable: " <> detail}
  end

  @doc "A fact the rules need was not supplied."
  @spec missing_fact(atom()) :: t()
  def missing_fact(name) when is_atom(name) do
    %__MODULE__{code: :missing_fact, message: "missing fact " <> Atom.to_string(name)}
  end
end
