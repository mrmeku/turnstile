defmodule ExampleRbac.Tightened do
  @moduledoc """
  The boot policy with one row changed: a program member holds
  `read_redacted` and no longer `read`. What the revocation and change
  scenarios publish.
  """

  use Boundary, top_level?: true, deps: [Example, ExampleRbac, Turnstile.Code]

  use Turnstile.Code.Policy,
    version: "2026.09.2-tightened",
    author: "example_rbac",
    approval: "docs/reference.md §3, tightened for the scenarios"

  alias Example.Assignment
  alias Example.Document
  alias Example.OfficeRole
  alias Example.Portion
  alias Example.Program
  alias Example.Proposal
  alias ExampleRbac.Predicates

  role :member, [:read_redacted]
  role :lead, [:read, :read_redacted]
  role :designator, [:read, :read_redacted, :change_marking, :set_decontrol, :decontrol, :propose_marking]
  role :approver, [:read, :read_redacted, :approve_marking]

  object Document do
    grant :assignment, Assignment, on: :program_id, through: [{Program, :id, where: &Predicates.open/0}]
    grant :office, OfficeRole, on: :designating_office_id
    predicate :controls, &Predicates.controls/2, only: [:read]
    predicate :session, &Predicates.session/2, only: [:change_marking, :set_decontrol, :decontrol]
  end

  object Portion do
    grant :assignment, Assignment,
      on: :document_id,
      through: [{Document, :program_id}, {Program, :id, where: &Predicates.open/0}]

    grant :office, OfficeRole, on: :document_id, through: [{Document, :designating_office_id}]
    predicate :controls, &Predicates.portion_controls/2, only: [:read]
    predicate :session, &Predicates.session/2, only: [:change_marking]
  end

  object Proposal do
    grant :office, OfficeRole, on: :document_id, through: [{Document, :designating_office_id}]
    predicate :another_approver, &Predicates.another_approver/2, only: [:approve_marking]
  end
end
