defmodule ExampleRbac.Policy do
  @moduledoc """
  The example's rules as a role table and, per protected schema, the
  grants and predicates of `docs/reference.md` §3. A program role reaches
  a document through its open program (C1) and a portion through its
  document; an office role reaches a document through its designating
  office (C1, C7) and a proposal through the document's office (C9). The
  controls predicate is C2, C3, C5, and C6 in one subquery; the session
  predicate is C8; the proposal predicate is C9.
  """

  use Turnstile.Code.Policy, version: "2026.09.1", author: "example_rbac", approval: "docs/reference.md §3"

  alias Example.Assignment
  alias Example.Document
  alias Example.OfficeRole
  alias Example.Portion
  alias Example.Program
  alias Example.Proposal
  alias ExampleRbac.Predicates

  role :member, [:read, :read_redacted]
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
