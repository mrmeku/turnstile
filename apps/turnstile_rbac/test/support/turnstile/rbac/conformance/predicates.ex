defmodule Turnstile.Rbac.Conformance.Predicates do
  @moduledoc """
  The predicates of the conformance role table: attribute checks as
  `dynamic` expressions over the row. The clearance is a fact of the
  account. The holding is a fact of the membership the grant reads, since a
  membership is unique per account and folder: the one on the row's folder
  must be held by the asking kind and not yet expired at the moment the
  port stamped the request with.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Membership
  alias Turnstile.Fixture.World

  @doc "The subject's account carries the clearance the fixture's rule asks for."
  @spec cleared(Turnstile.subject(), Turnstile.environment()) :: Ecto.Query.dynamic_expr()
  def cleared({_kind, id}, %{now: _now}) do
    cleared = World.cleared()
    dynamic([_row], exists(from(a in Account, where: a.id == ^id and a.clearance == ^cleared)))
  end

  @doc "The folder row's membership for the subject is held by its kind and is live."
  @spec held(Turnstile.subject(), Turnstile.environment()) :: Ecto.Query.dynamic_expr()
  def held(subject, %{now: _now} = environment) do
    dynamic([row], row.id in subquery(live(subject, environment)))
  end

  @doc "The item row's folder has a membership for the subject held by its kind and live."
  @spec folder_held(Turnstile.subject(), Turnstile.environment()) :: Ecto.Query.dynamic_expr()
  def folder_held(subject, %{now: _now} = environment) do
    dynamic([row], row.folder_id in subquery(live(subject, environment)))
  end

  # The folders on which the subject's membership is held by its kind and
  # has not expired.
  defp live({kind, id}, %{now: now}) do
    from(m in Membership,
      where: m.account_id == ^id and m.subject_kind == ^kind,
      where: is_nil(m.expires_at) or m.expires_at > ^now,
      select: m.folder_id
    )
  end
end
