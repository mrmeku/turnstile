defmodule Turnstile.Reason do
  @moduledoc "Why the verdict is what it is, in a form a record can carry without attribute values."

  alias Turnstile.Edge
  alias Turnstile.Error

  @codes [
    :allowed,
    :deny_by_default,
    :rule_denied,
    :engine_unreachable,
    :missing_fact,
    :unknown_operation,
    :unknown_subject_kind
  ]

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

  @doc "The codes, in the order the type lists them."
  @spec codes() :: [code()]
  def codes, do: @codes

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

  @doc "No rule knows the operation."
  @spec unknown_operation(atom()) :: t()
  def unknown_operation(operation) when is_atom(operation) do
    %__MODULE__{code: :unknown_operation, message: "unknown operation " <> Atom.to_string(operation)}
  end

  @doc "The subject's kind is none of the three the port dispatches on."
  @spec unknown_subject_kind(term()) :: t()
  def unknown_subject_kind(kind) do
    %__MODULE__{code: :unknown_subject_kind, message: "unknown subject kind " <> inspect(kind)}
  end

  @doc "The reason as a map of plain values."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{code: code, message: message, rule: rule}) do
    %{code: Atom.to_string(code), message: message, rule: rule}
  end

  @doc "A map back to the reason."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def from_map(map) when is_map(map) do
    spec = [code: {:in, @codes}, message: :string, rule: {:string, :nil_ok}]

    with {:ok, fields} <- Edge.convert(map, spec, :reason, [:rule]) do
      {:ok, struct!(__MODULE__, fields)}
    end
  end
end
