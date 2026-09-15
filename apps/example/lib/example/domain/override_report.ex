defmodule Example.Domain.OverrideReport do
  @moduledoc "One audited override, reported to the document's designating office. No rule reads it."

  use Ecto.Schema

  alias Example.Domain.Document
  alias Example.Domain.Office

  @type t :: %__MODULE__{}

  schema "override_reports" do
    field(:user_id, :string)
    field(:justification, :string)
    field(:operation_id, :string)
    field(:at, :utc_datetime)
    belongs_to(:document, Document)
    belongs_to(:office, Office)
  end
end
