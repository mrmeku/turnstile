defmodule ExampleCerbos.Core.Controls do
  @moduledoc false
  # Hidden, because what the sidecar reads is an attribute declaration, not
  # this. What is here is the one derivation the policy language does not
  # carry: which controls are effective on a marking. A control is effective
  # when the marking declares it or a specified category the marking names
  # implies it (C3), which is a union over the control names, one query per
  # name, each selecting the row and the name as text. A portion is
  # controlled while its document is (C4, C5), a date on a row the portion
  # does not carry, so the moment arrives as an argument and the test is
  # inside the subquery.

  import Ecto.Query, only: [from: 2, union_all: 2]

  alias Example.Domain.Category
  alias Example.Domain.Controls
  alias Example.Domain.Document
  alias Example.Domain.Marking
  alias Example.Domain.Portion

  @doc "The controls effective on each document's banner, declared or implied."
  @spec on_documents() :: Ecto.Query.t()
  def on_documents, do: union_of(&document_control/1)

  @doc "The controls effective on each portion's own marking, while its document is controlled at `at`."
  @spec on_portions(DateTime.t()) :: Ecto.Query.t()
  def on_portions(%DateTime{} = at), do: union_of(&portion_control(&1, at))

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
  defp portion_control(control, at) do
    name = Atom.to_string(control)

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
end
