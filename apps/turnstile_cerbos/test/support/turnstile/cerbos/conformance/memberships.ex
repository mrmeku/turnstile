defmodule Turnstile.Cerbos.Conformance.Memberships do
  @moduledoc """
  The fixture's memberships as the two subqueries the declarations name: the
  roles an account holds on a folder, and the roles it holds on the folder
  an item is in. Each selects the row the value belongs to and the value as
  text, since a policy compares text.
  """

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Subject

  @doc "The roles the subject holds, by folder."
  @spec folder_roles_for(Subject.t()) :: Ecto.Query.t()
  def folder_roles_for(%Subject{id: id}) do
    from(m in Membership, where: m.account_id == ^id, select: %{id: m.folder_id, value: type(m.role, :string)})
  end

  @doc "The roles the subject holds on each item's folder, by item."
  @spec item_roles_for(Subject.t()) :: Ecto.Query.t()
  def item_roles_for(%Subject{id: id}) do
    from(i in Item,
      join: m in Membership,
      on: m.folder_id == i.folder_id,
      where: m.account_id == ^id,
      select: %{id: i.id, value: type(m.role, :string)}
    )
  end
end
