defmodule ExampleCerbos.Facts do
  @moduledoc """
  The subqueries the attribute declarations name, one per attribute whose
  value depends on who is asking or on a derivation the policies do not
  carry. Each selects the row the value belongs to and the value as text,
  since text is what a policy compares.

  Two derivations live here rather than in a policy. A control is effective
  on a marking when the marking declares it or a specified category the
  marking names implies it (C3), which is a union over the control names;
  and a portion is controlled while its document is (C4, C5), which is a
  date on a row the portion does not carry, so the test is inside the
  subquery. The moment that test compares against is the clock the
  configuration names, the same clock the port stamps a request with.

  Every column read here is a declared fact of the example, which
  `ExampleCerbos.CoverageTest` sets against the declarations.
  """

  import Ecto.Query, only: [from: 2, union_all: 2]

  alias Example.Agency
  alias Example.Assignment
  alias Example.Category
  alias Example.Controls
  alias Example.Document
  alias Example.Marking
  alias Example.Office
  alias Example.OfficeRole
  alias Example.Portion
  alias Example.Program
  alias Example.Proposal
  alias Example.User
  alias Turnstile.Config
  alias Turnstile.Subject

  @doc "The roles the subject holds through an open program, by document (C1)."
  @spec program_roles(Subject.t()) :: Ecto.Query.t()
  def program_roles(%Subject{id: id}) do
    from(a in Assignment,
      join: p in Program,
      on: p.id == a.program_id,
      join: d in Document,
      on: d.program_id == p.id,
      where: a.user_id == ^id and is_nil(p.closed_at),
      select: %{id: d.id, value: type(a.role, :string)}
    )
  end

  @doc "The roles the subject holds in a document's designating office, by document (C1)."
  @spec office_roles(Subject.t()) :: Ecto.Query.t()
  def office_roles(%Subject{id: id}) do
    from(r in OfficeRole,
      join: d in Document,
      on: d.designating_office_id == r.office_id,
      where: r.user_id == ^id,
      select: %{id: d.id, value: type(r.role, :string)}
    )
  end

  @doc "The controls effective on a document's banner, declared or implied, by document (C2, C3)."
  @spec effective_controls(Subject.t()) :: Ecto.Query.t()
  def effective_controls(%Subject{}) do
    union_of(&document_control/1)
  end

  @doc "The subject's nationality where a document's banner releases to it, by document (C2)."
  @spec releasable_to(Subject.t()) :: Ecto.Query.t()
  def releasable_to(%Subject{id: id}) do
    from(m in Marking,
      join: u in User,
      on: u.id == ^id,
      where: u.nationality in m.releasable_to,
      select: %{id: m.document_id, value: u.nationality}
    )
  end

  @doc "The nationality of the agency a document's designating office belongs to, by document (C2)."
  @spec agency_nationalities(Subject.t()) :: Ecto.Query.t()
  def agency_nationalities(%Subject{}) do
    from(d in Document,
      join: o in Office,
      on: o.id == d.designating_office_id,
      join: a in Agency,
      on: a.id == o.agency_id,
      select: %{id: d.id, value: a.nationality}
    )
  end

  @doc "The subject's own id where a document's banner lists it, by document (C6)."
  @spec listed(Subject.t()) :: Ecto.Query.t()
  def listed(%Subject{id: id}) do
    from(m in Marking,
      where: ^id in m.list,
      select: %{id: m.document_id, value: type(^id, :string)}
    )
  end

  @doc "The roles the subject holds through an open program, by portion (C1)."
  @spec portion_program_roles(Subject.t()) :: Ecto.Query.t()
  def portion_program_roles(%Subject{id: id}) do
    from(a in Assignment,
      join: p in Program,
      on: p.id == a.program_id,
      join: d in Document,
      on: d.program_id == p.id,
      join: portion in Portion,
      on: portion.document_id == d.id,
      where: a.user_id == ^id and is_nil(p.closed_at),
      select: %{id: portion.id, value: type(a.role, :string)}
    )
  end

  @doc "The roles the subject holds in the designating office of a portion's document, by portion (C1)."
  @spec portion_office_roles(Subject.t()) :: Ecto.Query.t()
  def portion_office_roles(%Subject{id: id}) do
    from(r in OfficeRole,
      join: d in Document,
      on: d.designating_office_id == r.office_id,
      join: portion in Portion,
      on: portion.document_id == d.id,
      where: r.user_id == ^id,
      select: %{id: portion.id, value: type(r.role, :string)}
    )
  end

  @doc "The controls effective on a portion's own marking while its document is controlled, by portion (C4, C5)."
  @spec portion_effective_controls(Subject.t()) :: Ecto.Query.t()
  def portion_effective_controls(%Subject{}) do
    union_of(&portion_control/1)
  end

  @doc "The subject's nationality where a portion's marking releases to it, by portion (C2)."
  @spec portion_releasable_to(Subject.t()) :: Ecto.Query.t()
  def portion_releasable_to(%Subject{id: id}) do
    from(portion in Portion,
      join: u in User,
      on: u.id == ^id,
      where: u.nationality in portion.releasable_to,
      select: %{id: portion.id, value: u.nationality}
    )
  end

  @doc "The nationality of the agency behind a portion's document, by portion (C2)."
  @spec portion_agency_nationalities(Subject.t()) :: Ecto.Query.t()
  def portion_agency_nationalities(%Subject{}) do
    from(portion in Portion,
      join: d in Document,
      on: d.id == portion.document_id,
      join: o in Office,
      on: o.id == d.designating_office_id,
      join: a in Agency,
      on: a.id == o.agency_id,
      select: %{id: portion.id, value: a.nationality}
    )
  end

  @doc "The subject's own id where the document of a portion lists it, by portion (C4, C6)."
  @spec portion_listed(Subject.t()) :: Ecto.Query.t()
  def portion_listed(%Subject{id: id}) do
    from(m in Marking,
      join: portion in Portion,
      on: portion.document_id == m.document_id,
      where: ^id in m.list,
      select: %{id: portion.id, value: type(^id, :string)}
    )
  end

  @doc "The roles the subject holds in the designating office of a proposal's document, by proposal (C9)."
  @spec proposal_office_roles(Subject.t()) :: Ecto.Query.t()
  def proposal_office_roles(%Subject{id: id}) do
    from(r in OfficeRole,
      join: d in Document,
      on: d.designating_office_id == r.office_id,
      join: proposal in Proposal,
      on: proposal.document_id == d.id,
      where: r.user_id == ^id,
      select: %{id: proposal.id, value: type(r.role, :string)}
    )
  end

  # One query per control name, combined: a control is one value of the
  # attribute, and which controls a row has is what the union answers.
  defp union_of(member) do
    [first | rest] = Enum.map(Controls.all(), member)

    Enum.reduce(rest, first, fn query, combined -> union_all(combined, ^query) end)
  end

  defp document_control(control) do
    name = Atom.to_string(control)

    from(m in Marking,
      left_join: c in Category,
      on: c.name in m.categories and c.specified,
      where: ^control in m.controls or ^control in c.implied_controls,
      distinct: true,
      select: %{id: m.document_id, value: type(^name, :string)}
    )
  end

  # The portion's own marking under the document's decontrol date: a portion
  # carries no date of its own, and a control the document has released is
  # effective on none of its portions.
  defp portion_control(control) do
    name = Atom.to_string(control)
    at = now()

    from(portion in Portion,
      join: d in Document,
      on: d.id == portion.document_id,
      left_join: c in Category,
      on: c.name in portion.categories and c.specified,
      where: ^control in portion.controls or ^control in c.implied_controls,
      where: is_nil(d.decontrol) or d.decontrol > ^at,
      distinct: true,
      select: %{id: portion.id, value: type(^name, :string)}
    )
  end

  # The clock the configuration names, cut to the second, which is the
  # precision the moment a request carries is cut to.
  defp now do
    {:ok, config} = Config.resolve()

    DateTime.truncate(config.clock.now(), :second)
  end
end
