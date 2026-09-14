defmodule Example.Core.ReviewQuery do
  @moduledoc false
  # Hidden, because the queries a context runs are not its surface. What is
  # here is the population `Example.Review` ranges over: every agency, every
  # account as the subject it stands for, and the documents an agency's
  # offices designated. The reviewer reads all three under a declared
  # exemption, so the rows are the whole of what there is to review.

  import Ecto.Query, only: [from: 2]

  alias Ecto.Query
  alias Example.Agency
  alias Example.Document
  alias Example.User

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
end
