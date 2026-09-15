defmodule Turnstile.Rbac.Conformance.Roles do
  @moduledoc """
  The fixture's rule as a role table: a reader may read, an editor may read
  and edit; a folder grants the role its memberships hold, an item grants
  the role its folder's memberships hold; every allowed subject is cleared;
  and the membership the grant reads is held by the asking kind and not yet
  expired. The relationship carries three attributes, so each grant names
  the role column.
  """

  use Turnstile.Rbac.Policy, version: "conformance", author: "turnstile_rbac", approval: "the conformance suite"

  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Rbac.Conformance.Predicates

  role :reader, [:read]
  role :editor, [:read, :edit]

  object Folder do
    grant :membership, Membership, role: :role
    predicate :cleared, &Predicates.cleared/2
    predicate :held, &Predicates.held/2
  end

  object Item do
    grant :folder_membership, Membership, on: :folder_id, role: :role
    predicate :cleared, &Predicates.cleared/2
    predicate :folder_held, &Predicates.folder_held/2
  end
end
