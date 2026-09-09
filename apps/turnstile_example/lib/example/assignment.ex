defmodule Example.Assignment do
  @moduledoc "Lawful purpose: an account holds a role, lead or member, on a program."

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Program

  @type t :: %__MODULE__{}

  schema "assignments" do
    field(:user_id, :string)
    field(:role, Ecto.Enum, values: [:lead, :member])
    belongs_to(:program, Program)
  end

  object_type(:assignment)
  relationship(subject: :user_id, object: :program_id, attributes: [:role])
end
