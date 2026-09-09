defmodule Example.ProposalsTest do
  use Example.FakeCase, async: true

  alias Example.Documents
  alias Example.Fixture
  alias Example.Marking
  alias Example.Proposal
  alias Example.Proposals
  alias Turnstile.Error

  @dana %Turnstile.Subject{id: "dana", kind: :user}
  @eve %Turnstile.Subject{id: "eve", kind: :user}

  setup %{world: world} do
    {:ok, document: Fixture.document!(world)}
  end

  test "propose needs the document's operation and records a pending proposal", ctx do
    assert {:error, %Error.NotAuthorized{operation: :propose_marking}} =
             Proposals.propose(@dana, ctx.document.id, %{controls: [:no_foreign]})

    allow(ctx.rules, "dana", :propose_marking, {:document, ctx.document.id})

    assert {:ok, %Proposal{status: :pending, proposer_id: "dana", controls: [:no_foreign]}} =
             Proposals.propose(@dana, ctx.document.id, %{controls: [:no_foreign]})

    assert {:ok, %Proposal{}} = Proposals.propose(@dana, ctx.document.id, %{"controls" => ["federal_only"]})
  end

  test "approve needs the proposal's operation, applies the marking, and closes the proposal", ctx do
    allow(ctx.rules, "dana", :propose_marking, {:document, ctx.document.id})
    {:ok, proposal} = Proposals.propose(@dana, ctx.document.id, %{controls: [:no_foreign]})
    assert {:error, %Error.NotAuthorized{operation: :approve_marking}} = Proposals.approve(@eve, proposal.id)
    allow(ctx.rules, "eve", :approve_marking, {:proposal, proposal.id})
    assert {:ok, %Proposal{status: :approved, approver_id: "eve"}} = Proposals.approve(@eve, proposal.id)
    assert {:error, :not_found} = Proposals.approve(@eve, proposal.id)
    allow(ctx.rules, "eve", :read, {:document, ctx.document.id})
    assert {:ok, %{marking: %Marking{controls: [:no_foreign]}}} = Documents.read(@eve, ctx.document.id)
    allow(ctx.rules, "eve", :approve_marking, {:proposal, :any})
    assert {:error, :not_found} = Proposals.approve(@eve, proposal.id + 1000)
  end

  test "an approval that would break the banner rolls back the proposal", ctx do
    document = Fixture.document!(ctx.world, portions: [%{body: "domestic", controls: [:no_foreign]}])
    allow(ctx.rules, "dana", :propose_marking, {:document, document.id})
    {:ok, proposal} = Proposals.propose(@dana, document.id, %{controls: []})
    allow(ctx.rules, "eve", :approve_marking, {:proposal, proposal.id})
    assert {:error, %Documents.BannerViolation{}} = Proposals.approve(@eve, proposal.id)
    assert %Proposal{status: :pending} = Example.Repo.get(Proposal, proposal.id, turnstile: Fixture.exemption())
  end

  test "pending lists a document's open proposals under the document's decision", ctx do
    allow(ctx.rules, "dana", :propose_marking, {:document, ctx.document.id})
    {:ok, proposal} = Proposals.propose(@dana, ctx.document.id, %{controls: [:no_foreign]})
    allow(ctx.rules, "dana", :read, {:document, ctx.document.id})
    {:ok, decision} = Turnstile.authorize(@dana, :read, Documents.object(ctx.document.id))
    assert [%Proposal{id: id}] = Proposals.pending(ctx.document, decision)
    assert id == proposal.id
  end
end
