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
