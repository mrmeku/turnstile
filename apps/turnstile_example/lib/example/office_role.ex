defmodule Example.OfficeRole do
  @moduledoc "An account holds a role, designator or approver, in an office."

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
  relationship(subject: :user_id, object: :office_id, attributes: [:role])
end
