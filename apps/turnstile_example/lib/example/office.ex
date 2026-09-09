defmodule Example.Office do
  @moduledoc "An office of an agency; a document's designating office is where designators and approvers hold roles."

  use Ecto.Schema
  use Turnstile.Schema

  alias Example.Agency

  @type t :: %__MODULE__{}

  schema "offices" do
    field(:name, :string)
    belongs_to(:agency, Agency)
  end

  object_type(:office)
  carries([:agency])
end
