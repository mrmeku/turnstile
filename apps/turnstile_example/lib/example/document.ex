defmodule Example.Document do
  @moduledoc """
  A document of a program, designated by an office, marked with a banner
  and decontrolled on a date or never. It carries its program, its
  designating office, its marking, and its proposals: a document decision
  admits queries on them. It does not carry its portions, which have their
  own object type and their own decisions.

  The document, the marking, the portion, and the proposal share this file
  because their associations refer to one another.
  """

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Marking
  alias Example.Office
  alias Example.Portion
  alias Example.Program
  alias Example.Proposal

  @type t :: %__MODULE__{}

  schema "documents" do
    field(:title, :string)
    field(:decontrol, :utc_datetime)
    belongs_to(:program, Program)
    belongs_to(:designating_office, Office)
    has_one(:marking, Marking)
    has_many(:portions, Portion)
    has_many(:proposals, Proposal)
  end

  object_type(:document)
  carries([:program, :designating_office, :marking, :proposals])
  fact(:decontrol, kind: :object_attribute, object: :id)
end

defmodule Example.Marking do
  @moduledoc """
  A document's banner: categories, controls, the countries REL TO releases
  to, and the DL ONLY list of accounts. Each set emits one fact event per
  element; the list is a relationship whose subjects are its elements.
  """

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Controls
  alias Example.Document

  @type t :: %__MODULE__{}

  schema "markings" do
    field(:categories, {:array, :string}, default: [])
    field(:controls, {:array, Ecto.Enum}, values: Controls.all(), default: [])
    field(:releasable_to, {:array, :string}, default: [])
    field(:list, {:array, :string}, default: [])
    belongs_to(:document, Document)
  end

  @doc "The marking fields, cast and validated; the list of accounts is a set."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = marking, attrs) when is_map(attrs) do
    marking
    |> Ecto.Changeset.cast(attrs, [:categories, :controls, :releasable_to, :list])
    |> Ecto.Changeset.update_change(:list, &Enum.sort(Enum.uniq(&1)))
  end

  object_type(:marking)
  fact(:categories, kind: :object_attribute, object: :document_id, element: :category)
  fact(:controls, kind: :object_attribute, object: :document_id, element: :control)
  fact(:releasable_to, kind: :object_attribute, object: :document_id, element: :country)
  fact(:list, kind: :relationship, subject: :element, object: :document_id, element: :user)
end

defmodule Example.Portion do
  @moduledoc "A portion of a document with a marking of its own; the document's banner is the union of them."

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Controls
  alias Example.Document

  @type t :: %__MODULE__{}

  schema "portions" do
    field(:body, :string)
    field(:categories, {:array, :string}, default: [])
    field(:controls, {:array, Ecto.Enum}, values: Controls.all(), default: [])
    field(:releasable_to, {:array, :string}, default: [])
    belongs_to(:document, Document)
  end

  @doc "The portion's marking fields, cast."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = portion, attrs) when is_map(attrs) do
    Ecto.Changeset.cast(portion, attrs, [:categories, :controls, :releasable_to])
  end

  object_type(:portion)
  fact(:categories, kind: :object_attribute, object: :id, element: :category)
  fact(:controls, kind: :object_attribute, object: :id, element: :control)
  fact(:releasable_to, kind: :object_attribute, object: :id, element: :country)
end

defmodule Example.Proposal do
  @moduledoc """
  A marking change proposed by one designator and approved by a different
  approver. The proposal carries its document, so the approval decision
  admits the marking it applies.
  """

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Controls
  alias Example.Document

  @type t :: %__MODULE__{}

  schema "marking_proposals" do
    field(:proposer_id, :string)
    field(:approver_id, :string)
    field(:status, Ecto.Enum, values: [:pending, :approved], default: :pending)
    field(:categories, {:array, :string}, default: [])
    field(:controls, {:array, Ecto.Enum}, values: Controls.all(), default: [])
    field(:releasable_to, {:array, :string}, default: [])
    field(:list, {:array, :string}, default: [])
    belongs_to(:document, Document)
  end

  @doc "A new proposal's marking fields, cast, with the proposer and the document."
  @spec changeset(t(), map()) :: Ecto.Changeset.t()
  def changeset(%__MODULE__{} = proposal, attrs) when is_map(attrs) do
    proposal
    |> Ecto.Changeset.cast(attrs, [:categories, :controls, :releasable_to, :list])
    |> Ecto.Changeset.validate_required([:proposer_id, :document_id])
  end

  @doc "The marking the proposal carries."
  @spec marking(t()) :: map()
  def marking(%__MODULE__{} = proposal) do
    Map.take(proposal, [:categories, :controls, :releasable_to, :list])
  end

  object_type(:proposal)
  carries([:document])
  relationship(subject: :proposer_id, object: :document_id, attributes: [:status])
end
