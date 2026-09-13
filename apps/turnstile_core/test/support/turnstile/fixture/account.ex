defmodule Turnstile.Fixture.Account do
  @moduledoc "An unprotected schema with one subject-attribute fact column."

  use Ecto.Schema
  use Turnstile.Schema

  @primary_key {:id, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "turnstile_fixture_accounts" do
    field(:clearance, :string)
  end

  fact(:clearance, kind: :subject_attribute, subject: :id)
end
