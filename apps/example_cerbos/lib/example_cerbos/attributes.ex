defmodule ExampleCerbos.Attributes do
  @moduledoc """
  What the policies of `priv/policies` may read: the attributes of a
  principal, of a document, of a portion, and of a proposal.

  A principal's two attributes are columns of the account row, so the
  sidecar folds a test over either of them before it plans anything, and
  the request-time fact `reauthenticated_at` reaches the policies beside
  the moment the port stamped the request with (C8).

  A resource attribute a policy tests membership in is a subquery of the
  asking subject (`ExampleCerbos.Facts`), so a list stays one query: the
  subquery selects the rows the value holds of, and the plan compiles the
  test to membership in those ids. A document's `decontrol` is a column
  instead, since the moment the policy compares it against is the moment
  the request carries (C5), which makes the comparison one the plan
  carries as a comparison on the row.

  Every column any of these reads is a declared fact of the example, which
  is a Tier 1 case of this application rather than a claim.
  """

  use Turnstile.Cerbos.Attributes

  alias Example.Document
  alias Example.Portion
  alias Example.Proposal
  alias Example.User
  alias ExampleCerbos.Facts

  principal :user, schema: User do
    attribute :employment, column: :employment
    attribute :nationality, column: :nationality
  end

  principal :non_person_entity, schema: User do
    attribute :employment, column: :employment
    attribute :nationality, column: :nationality
  end

  principal :privileged, schema: User do
    attribute :employment, column: :employment
    attribute :nationality, column: :nationality
  end

  resource :document, schema: Document do
    attribute :program_roles, subquery: &Facts.program_roles/1
    attribute :office_roles, subquery: &Facts.office_roles/1
    attribute :effective_controls, subquery: &Facts.effective_controls/1
    attribute :releasable_to, subquery: &Facts.releasable_to/1
    attribute :agency_nationalities, subquery: &Facts.agency_nationalities/1
    attribute :listed, subquery: &Facts.listed/1
    attribute :decontrol, column: :decontrol
  end

  resource :portion, schema: Portion do
    attribute :program_roles, subquery: &Facts.portion_program_roles/1
    attribute :office_roles, subquery: &Facts.portion_office_roles/1
    attribute :effective_controls, subquery: &Facts.portion_effective_controls/1
    attribute :releasable_to, subquery: &Facts.portion_releasable_to/1
    attribute :agency_nationalities, subquery: &Facts.portion_agency_nationalities/1
    attribute :listed, subquery: &Facts.portion_listed/1
  end

  resource :proposal, schema: Proposal do
    attribute :office_roles, subquery: &Facts.proposal_office_roles/1
    attribute :proposer_id, column: :proposer_id
  end

  environment do
    fact(:reauthenticated_at)
  end
end
