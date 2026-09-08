defmodule Turnstile.FactEvent do
  @moduledoc """
  One change to one authorization fact, with the value before and after.
  A relationship row's existence is the grant, so its insert and delete are
  events too. A policy version is the fourth kind: `subject_ref` is `nil`,
  `object_ref` is `{:policy, adapter}`, `attribute` is `:version`, and `new`
  is a `Turnstile.PolicyVersion`.
  """

  @enforce_keys [:kind, :subject_ref, :object_ref, :attribute, :old, :new, :position, :operation_id, :at, :by]
  defstruct @enforce_keys

  @type kind :: :subject_attribute | :object_attribute | :relationship | :policy_version

  @typedoc "`position` is `nil` in ledger mode none; `by` is the subject of the operation that wrote it."
  @type t :: %__MODULE__{
          kind: kind(),
          subject_ref: Turnstile.Object.ref() | nil,
          object_ref: Turnstile.Object.ref(),
          attribute: atom(),
          old: term(),
          new: term(),
          position: non_neg_integer() | nil,
          operation_id: Turnstile.Id.t(),
          at: DateTime.t(),
          by: Turnstile.Subject.t()
        }

  @doc "The four kinds, in the order the reference lists them."
  @spec kinds() :: [kind()]
  def kinds, do: [:subject_attribute, :object_attribute, :relationship, :policy_version]
end
