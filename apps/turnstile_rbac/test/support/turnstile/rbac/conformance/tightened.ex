defmodule Turnstile.Rbac.Conformance.Tightened do
  @moduledoc """
  The fixture's rule tightened: the same objects, grants, and predicates as
  `Turnstile.Rbac.Conformance.Roles`, under a role table where an editor
  may edit and no longer read. The change-management laws publish it as
  the version after the boot one and expect the granted editor to be
  denied the read it held.
  """

  use Turnstile.Rbac.Policy,
    version: "conformance-tightened",
    author: "turnstile_rbac",
    approval: "the conformance suite"

  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Rbac.Conformance.Predicates

  role :reader, [:read]
  role :editor, [:edit]

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
