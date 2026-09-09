defmodule Example.ProposalController do
  @moduledoc "Marking proposals over JSON: propose on a document, approve by id."

  use Phoenix.Controller, formats: [:json]

  alias Example.Controls
  alias Example.Proposals

  @doc "Propose a marking for a document."
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def create(conn, %{"id" => id} = params) do
    attrs = Map.delete(params, "id")

    case Proposals.propose(conn.assigns.subject, String.to_integer(id), attrs, facts: conn.assigns.facts) do
      {:ok, proposal} -> created(conn, proposal)
      {:error, _refusal} -> forbidden(conn)
    end
  end

  @doc "Approve a proposal."
  @spec approve(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def approve(conn, %{"id" => id}) do
    case Proposals.approve(conn.assigns.subject, String.to_integer(id), facts: conn.assigns.facts) do
      {:ok, proposal} -> json(conn, Controls.marking(proposal.document.marking))
      {:error, _refusal} -> forbidden(conn)
    end
  end

  defp created(conn, proposal) do
    conn
    |> put_status(201)
    |> json(%{id: proposal.id, status: proposal.status})
  end

  defp forbidden(conn) do
    conn
    |> put_status(403)
    |> json(%{error: "forbidden"})
  end
end
