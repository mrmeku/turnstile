defmodule Example.Proposals do
  @moduledoc """
  Separation of duties on marking changes (C9): a designator proposes, a
  different approver approves, and the approval applies the marking under
  the proposal's decision, which carries the document and the document's
  marking, so the approval writes both as nested changes of the proposal.
  A proposal without approval changes nothing.
  """

  alias Example.Document
  alias Example.Documents
  alias Example.Proposal
  alias Example.Repo
  alias Turnstile.Subject

  @doc "Propose a marking for a document; needs `propose_marking` on the document (C7)."
  @spec propose(Subject.t(), integer(), map(), keyword()) :: {:ok, Proposal.t()} | {:error, Documents.refusal()}
  def propose(%Subject{id: proposer} = subject, document_id, attrs, opts \\ [])
      when is_integer(document_id) and is_map(attrs) do
    with {:ok, decision} <- Turnstile.authorize(subject, :propose_marking, Documents.object(document_id), opts),
         {:ok, document} <- Documents.fetch(document_id, decision) do
      proposal = Proposal.changeset(%Proposal{proposer_id: proposer, document_id: document.id}, attrs)
      change = appended(document, proposal, decision)

      with {:ok, %Document{proposals: proposals}} <- Repo.update(change, turnstile: decision) do
        {:ok, List.last(proposals)}
      end
    end
  end

  @doc "Approve a proposal; needs `approve_marking` on it, which C9 gives a different approver alone."
  @spec approve(Subject.t(), integer(), keyword()) ::
          {:ok, Proposal.t()} | {:error, Documents.refusal() | Documents.BannerViolation.t()}
  def approve(%Subject{id: approver} = subject, proposal_id, opts \\ []) when is_integer(proposal_id) do
    object = Documents.object(:proposal, proposal_id)

    with {:ok, decision} <- Turnstile.authorize(subject, :approve_marking, object, opts),
         %Proposal{status: :pending} = proposal <-
           Repo.get(Proposal, proposal_id, turnstile: decision) || {:error, :not_found} do
      Repo.transaction(fn -> approve_or_roll_back(proposal, approver, decision) end)
    else
      %Proposal{status: :approved} -> {:error, :not_found}
      other -> other
    end
  end

  @doc "The pending proposals of a document, oldest first, under a decision on the document."
  @spec pending(Document.t(), Turnstile.Decision.t()) :: [Proposal.t()]
  def pending(%Document{} = document, %Turnstile.Decision{} = decision) do
    document
    |> Repo.preload(:proposals, turnstile: decision)
    |> Map.fetch!(:proposals)
    |> Enum.filter(&(&1.status == :pending))
    |> Enum.sort_by(& &1.id)
  end

  # Inside the transaction: the proposal, its document, and the document's marking as one nested write.
  defp approve_or_roll_back(%Proposal{} = proposal, approver, decision) do
    proposal = Repo.preload(proposal, [document: :marking], turnstile: decision)

    case Documents.marking_change(proposal.document, Proposal.marking(proposal)) do
      {:ok, document_change} ->
        proposal
        |> Ecto.Changeset.change(status: :approved, approver_id: approver)
        |> Ecto.Changeset.put_assoc(:document, document_change)
        |> Repo.update!(turnstile: decision)

      {:error, violation} ->
        Repo.rollback(violation)
    end
  end

  # The document's proposals with one more, as a nested change the document's decision carries.
  defp appended(%Document{} = document, proposal, decision) do
    document = Repo.preload(document, :proposals, turnstile: decision)

    document
    |> Ecto.Changeset.change()
    |> Ecto.Changeset.put_assoc(:proposals, Enum.reverse([proposal | Enum.reverse(document.proposals)]))
  end
end
