defmodule Turnstile.Cerbos.Conformance do
  @moduledoc """
  The conformance artifact of the Cerbos adapter: the attribute
  declarations and the subqueries behind them, which encode where the
  neutral fixture's values come from. The policies that read those
  attributes sit beside this file as YAML, which is what the sidecar reads.
  The test run compiles the module; an application never loads it.
  """

  use Boundary,
    top_level?: true,
    deps: [Turnstile, Turnstile.Cerbos, Turnstile.Fixture, Ecto],
    exports: [Attributes, Memberships]
end

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

defmodule Turnstile.Cerbos.Conformance.Attributes do
  @moduledoc """
  What the conformance policies read: the account's clearance for the
  principal, and the roles the asking account holds over the row for a
  folder and for an item.

  Every subject kind is declared, each against the account row, because the
  fixture's rule turns on what an account holds and not on which kind is
  asking, and a kind that is not declared has no attributes to send.
  """

  use Turnstile.Cerbos.Attributes

  alias Turnstile.Cerbos.Conformance.Memberships
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item

  principal :user, schema: Account do
    attribute :clearance, column: :clearance
  end

  principal :non_person_entity, schema: Account do
    attribute :clearance, column: :clearance
  end

  principal :privileged, schema: Account do
    attribute :clearance, column: :clearance
  end

  resource :folder, schema: Folder do
    attribute :member_roles, subquery: &Memberships.folder_roles_for/1
  end

  resource :item, schema: Item do
    attribute :member_roles, subquery: &Memberships.item_roles_for/1
  end
end
