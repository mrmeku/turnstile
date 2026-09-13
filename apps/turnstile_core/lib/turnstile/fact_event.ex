defmodule Turnstile.FactEvent do
  @moduledoc """
  One change to one authorization fact, with the value before and after.
  A relationship row's existence is the grant, so its insert and delete are
  events too. A policy version is the fourth kind: `subject_ref` is `nil`,
  `object_ref` is `{:policy, adapter}`, `attribute` is `:version`, and `new`
  is a `Turnstile.PolicyVersion`.
  """

  alias Turnstile.Edge
  alias Turnstile.Error
  alias Turnstile.PolicyVersion

  @kinds [:subject_attribute, :object_attribute, :relationship, :policy_version]
  @library {:non_person_entity, "00000000-0000-0000-0000-000000000000"}

  @enforce_keys [:kind, :subject_ref, :object_ref, :attribute, :old, :new, :position, :operation_id, :at, :by]
  defstruct @enforce_keys

  @type kind :: :subject_attribute | :object_attribute | :relationship | :policy_version

  @typedoc "`position` is `nil` in ledger mode none; `by` is the subject of the operation that wrote it."
  @type t :: %__MODULE__{
          kind: kind(),
          subject_ref: Turnstile.object() | nil,
          object_ref: Turnstile.object(),
          attribute: atom(),
          old: term(),
          new: term(),
          position: non_neg_integer() | nil,
          operation_id: Turnstile.Id.t(),
          at: DateTime.t(),
          by: Turnstile.subject()
        }

  @doc "The four kinds, in the order the reference lists them."
  @spec kinds() :: [kind()]
  def kinds, do: @kinds

  @doc """
  The writer of an event no decision names, which is the library itself: a
  non-person entity with the nil identifier.
  """
  @spec library() :: Turnstile.subject()
  def library, do: @library

  @doc """
  A subject as `subject_ref` names it. A fact about a subject is a fact
  about the account, so the reference is `{:user, id}` whatever the kind of
  the subject that asked.
  """
  @spec subject_ref(Turnstile.subject()) :: Turnstile.object()
  def subject_ref({_kind, id}), do: {:user, id}

  @doc "The event as a map of plain values; a policy version in `new` becomes its own map."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = event) do
    %{
      kind: Atom.to_string(event.kind),
      subject_ref: Edge.ref_out(event.subject_ref),
      object_ref: Edge.ref_out(event.object_ref),
      attribute: Edge.atom_out(event.attribute),
      old: value_out(event.old),
      new: value_out(event.new),
      position: event.position,
      operation_id: event.operation_id,
      at: Edge.time_out(event.at),
      by: Edge.ref_out(event.by)
    }
  end

  @doc "A map back to the event."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def from_map(map) when is_map(map) do
    with {:ok, fields} <- Edge.convert(map, spec(), :fact_event),
         {:ok, old} <- value_in(fields[:kind], fields[:old]),
         {:ok, new} <- value_in(fields[:kind], fields[:new]) do
      {:ok, struct!(__MODULE__, Keyword.merge(fields, old: old, new: new))}
    end
  end

  defp spec do
    [
      kind: {:in, @kinds},
      subject_ref: :ref,
      object_ref: :ref,
      attribute: :atom,
      old: :any,
      new: :any,
      position: {:integer, :nil_ok},
      operation_id: :string,
      at: :time,
      by: :ref
    ]
  end

  defp value_out(%PolicyVersion{} = version), do: PolicyVersion.to_map(version)
  defp value_out(value), do: value

  defp value_in(:policy_version, %PolicyVersion{} = version), do: {:ok, version}
  defp value_in(:policy_version, map) when is_map(map), do: PolicyVersion.from_map(map)
  defp value_in(_kind, value), do: {:ok, value}
end
