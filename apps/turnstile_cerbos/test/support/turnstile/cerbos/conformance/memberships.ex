defmodule Turnstile.Cerbos.Conformance.Memberships do
  @moduledoc """
  The fixture's memberships as the two subqueries the declarations name: the
  roles an account holds on a folder, and the roles it holds on the folder
  an item is in. Each selects the row the value belongs to and the value as
  text, since a policy compares text. A membership counts when the asking
  kind holds it and it has not expired at the moment the request carries,
  so what the policy reads as a role is a live grant to this subject.
  """

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

  @doc "The roles the subject holds live, by folder."
  @spec folder_roles_for(Turnstile.subject(), Turnstile.environment()) :: Ecto.Query.t()
  def folder_roles_for({kind, id}, %{now: now}) do
    from(m in Membership,
      where: m.account_id == ^id and m.subject_kind == ^kind,
      where: is_nil(m.expires_at) or m.expires_at > ^now,
      select: %{id: m.folder_id, value: type(m.role, :string)}
    )
  end

  @doc "The roles the subject holds live on each item's folder, by item."
  @spec item_roles_for(Turnstile.subject(), Turnstile.environment()) :: Ecto.Query.t()
  def item_roles_for({kind, id}, %{now: now}) do
    from(i in Item,
      join: m in Membership,
      on: m.folder_id == i.folder_id,
      where: m.account_id == ^id and m.subject_kind == ^kind,
      where: is_nil(m.expires_at) or m.expires_at > ^now,
      select: %{id: i.id, value: type(m.role, :string)}
    )
  end
end
