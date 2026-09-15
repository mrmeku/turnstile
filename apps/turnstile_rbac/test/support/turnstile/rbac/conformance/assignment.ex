defmodule Turnstile.Rbac.Conformance.Assignment do
  @moduledoc """
  A relationship that declares two attributes. A grant over a relationship
  with one attribute needs no naming, so this is what the rule that a wider
  relationship names its role column is read against.
  """

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Fixture.Folder

  @type t :: %__MODULE__{}

  schema "turnstile_code_assignments" do
    field(:account_id, :string)
    field(:role, Ecto.Enum, values: [:reader, :editor])
    field(:scope, :string)
    belongs_to(:folder, Folder)
  end

  audited(:role)
  relationship(subject: :account_id, object: :folder_id, attributes: [:role, :scope])
end
