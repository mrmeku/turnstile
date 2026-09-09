defmodule Example.Program do
  @moduledoc "A program of an office. Assignment to it is lawful purpose; closing it ends every assignment's purpose."

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Office

  @type t :: %__MODULE__{}

  schema "programs" do
    field(:name, :string)
    field(:closed_at, :utc_datetime)
    belongs_to(:office, Office)
  end

  object_type(:program)
  fact(:closed_at, kind: :object_attribute, object: :id)
end
