defmodule Turnstile.Code.Conformance.Predicates do
  @moduledoc "The predicates of the conformance role table: attribute checks as `dynamic` expressions over the row."

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Turnstile.Environment
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.World
  alias Turnstile.Subject

  @doc "The subject's account carries the clearance the fixture's rule asks for."
  @spec cleared(Subject.t(), Environment.t()) :: Ecto.Query.dynamic_expr()
  def cleared(%Subject{id: id}, %Environment{}) do
    cleared = World.cleared()
    dynamic([_row], exists(from(a in Account, where: a.id == ^id and a.clearance == ^cleared)))
  end
end
