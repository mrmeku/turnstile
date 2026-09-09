defmodule Example.Agency do
  @moduledoc "The tenant. Its nationality is what NOFORN compares a subject's nationality with."

  use Ecto.Schema
  use Turnstile.Schema

  @type t :: %__MODULE__{}

  schema "agencies" do
    field(:name, :string)
    field(:nationality, :string)
  end

  object_type(:agency)
  fact(:nationality, kind: :object_attribute, object: :id)
end
