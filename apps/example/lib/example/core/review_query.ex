defmodule Example.Core.ReviewQuery do
  @moduledoc false
  # Hidden, because the queries a context runs are not its surface. What is
  # here is the population `Example.Review` ranges over: every agency, every
  # account as the subject it stands for, and the documents an agency's
  # offices designated. The reviewer reads all three under a declared
  # exemption, so the rows are the whole of what there is to review. The
  # proposals over those documents are the population of `approve_marking`.

  import Ecto.Query, only: [from: 2]

  alias Ecto.Query
  alias Example.Domain.Agency
  alias Example.Domain.Document
  alias Example.Domain.Proposal
  alias Example.Domain.User

  @doc "Every agency, in id order."
  @spec agencies() :: Query.t()
  def agencies, do: from(a in Agency, order_by: a.id)

  @doc "Every account as its id and its kind, in id order, which the caller reads as a subject."
  @spec subjects() :: Query.t()
  def subjects, do: from(u in User, order_by: u.id, select: {u.id, u.kind})

  @doc "The ids of the documents the offices of an agency designated, in id order."
  @spec documents(integer()) :: Query.t()
  def documents(agency_id) when is_integer(agency_id) do
    from(d in Document,
      join: o in assoc(d, :designating_office),
      where: o.agency_id == ^agency_id,
      order_by: d.id,
      select: d.id
    )
  end

  @doc "The ids of the proposals over the documents the offices of an agency designated, in id order."
  @spec proposals(integer()) :: Query.t()
  def proposals(agency_id) when is_integer(agency_id) do
    from(p in Proposal,
      join: d in assoc(p, :document),
      join: o in assoc(d, :designating_office),
      where: o.agency_id == ^agency_id,
      order_by: p.id,
      select: p.id
    )
  end
end
