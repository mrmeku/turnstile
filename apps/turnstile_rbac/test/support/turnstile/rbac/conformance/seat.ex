defmodule Turnstile.Rbac.Conformance.Seat do
  @moduledoc """
  The fixture's memberships read as a relationship that declares one
  attribute, the role alone. A grant over such a relationship needs no
  naming of its role column, so this is what that default is read against
  now that the fixture's own membership carries the kind and the expiry
  beside the role.
  """

  use Ecto.Schema
  use Turnstile.Schema

  alias Turnstile.Fixture.Folder

  @type t :: %__MODULE__{}

  schema "turnstile_fixture_memberships" do
    field(:account_id, :string)
    field(:role, Ecto.Enum, values: [:reader, :editor])
    belongs_to(:folder, Folder)
  end

  audited(:role)
  relationship(subject: :account_id, object: :folder_id, attributes: [:role])
end
