defmodule Example.AccountRole do
  @moduledoc """
  A role an account holds outside any program or office: `override` is the
  permission the audited override needs, held by a privileged account and
  never by an ordinary one. The role is a subject attribute; the table
  declares no object type and is written under a declared exemption by
  role administration.
  """

  use Ecto.Schema
  use Turnstile.Schema

  @type t :: %__MODULE__{}

  schema "account_roles" do
    field(:user_id, :string)
    field(:role, Ecto.Enum, values: [:override])
  end

  fact(:role, kind: :subject_attribute, subject: :user_id)
end
