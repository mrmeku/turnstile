defmodule Example.OfficeRole do
  @moduledoc """
  An account holds a role, designator or approver, in an office. The table
  admits both roles for one account in one office, so the row is declared
  twice over: as the relationship a review of a past date reports, and as an
  object of its own carrying its account, its office, and its role, which is
  what tells the two roles apart where a fold keys a relationship by its
  subject and its object alone.
  """

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Office

  @type t :: %__MODULE__{}

  schema "office_roles" do
    field(:user_id, :string)
    field(:role, Ecto.Enum, values: [:designator, :approver])
    belongs_to(:office, Office)
  end

  object_type(:office_role)
  fact(:user_id, kind: :object_attribute, object: :id)
  fact(:office_id, kind: :object_attribute, object: :id)
  fact(:role, kind: :object_attribute, object: :id)
  relationship(subject: :user_id, object: :office_id, attributes: [:role])
end
