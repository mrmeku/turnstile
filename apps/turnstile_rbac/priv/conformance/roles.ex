defmodule Turnstile.Code.Conformance do
  @moduledoc """
  The conformance artifact of RBAC in code: the role table and the
  predicates that encode the neutral fixture's rule, the modules the
  conformance suite binds. The test run compiles them; an application never
  loads them.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Code, Turnstile.Fixture, Ecto], exports: [Predicates, Roles]
end

defmodule Turnstile.Code.Conformance.Roles do
  @moduledoc """
  The fixture's rule as a role table: a reader may read, an editor may read
  and edit; a folder grants the role its memberships hold, an item grants
  the role its folder's memberships hold; and every allowed subject is
  cleared.
  """

  use Turnstile.Code.Policy, version: "conformance", author: "turnstile_rbac", approval: "the conformance suite"

  alias Turnstile.Code.Conformance.Predicates
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

  role :reader, [:read]
  role :editor, [:read, :edit]

  object Folder do
    grant :membership, Membership
    predicate :cleared, &Predicates.cleared/2
  end

  object Item do
    grant :folder_membership, Membership, on: :folder_id
    predicate :cleared, &Predicates.cleared/2
  end
end
