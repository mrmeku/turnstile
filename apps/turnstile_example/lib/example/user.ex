defmodule Example.User do
  @moduledoc """
  An account. A person may hold two: an ordinary one and a privileged one,
  joined by `person_id` and never by permission. Employment and nationality
  are the subject attributes the controls test.
  """

  use Ecto.Schema
  use Turnstile.Schema

  @primary_key {:id, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "users" do
    field(:name, :string)
    field(:kind, Ecto.Enum, values: [:user, :privileged])
    field(:person_id, :string)
    field(:employment, Ecto.Enum, values: [:federal, :contractor])
    field(:nationality, :string)
  end

  fact(:employment, kind: :subject_attribute, subject: :id)
  fact(:nationality, kind: :subject_attribute, subject: :id)
end
