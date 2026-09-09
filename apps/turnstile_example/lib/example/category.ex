defmodule Example.Category do
  @moduledoc "A Registry category. A specified category implies controls, read at every check and never copied."

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Controls

  @primary_key {:name, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "categories" do
    field(:specified, :boolean, default: false)
    field(:implied_controls, {:array, Ecto.Enum}, values: Controls.all(), default: [])
  end

  object_type(:category)
  fact(:specified, kind: :object_attribute, object: :name)
  fact(:implied_controls, kind: :object_attribute, object: :name, element: :control)
end
