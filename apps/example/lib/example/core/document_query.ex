defmodule Example.Core.DocumentQuery do
  @moduledoc false
  # Hidden, because the queries a context runs are not its surface. What is
  # here is which rows `Example.Documents` asks for: the documents a rule
  # admits, the portions of a document, and the overrides reported to an
  # office. A rule is the `dynamic` the port's `scope` answered with, and it
  # is carried into the query rather than read, so nothing here decides who
  # may see a row.

  import Ecto.Query, only: [from: 2, where: 2]

  alias Ecto.Query
  alias Example.Domain.Document
  alias Example.Domain.OverrideReport
  alias Example.Domain.Portion

  @doc "The documents a rule admits, in id order, each with its banner."
  @spec listed(Query.dynamic_expr()) :: Query.t()
  def listed(rule), do: from(d in Document, where: ^rule, order_by: d.id, preload: :marking)

  @doc "Every portion of a document, which the banner is derived from."
  @spec portions(integer()) :: Query.t()
  def portions(document_id) when is_integer(document_id), do: where(Portion, document_id: ^document_id)

  @doc "The portions of a document a rule admits, in id order."
  @spec portions(integer(), Query.dynamic_expr()) :: Query.t()
  def portions(document_id, rule) when is_integer(document_id) do
    from(p in Portion, where: p.document_id == ^document_id, where: ^rule, order_by: p.id)
  end

  @doc "The overrides reported to an office, oldest first."
  @spec reports(integer()) :: Query.t()
  def reports(office_id) when is_integer(office_id) do
    from(r in OverrideReport, where: r.office_id == ^office_id, order_by: r.id)
  end
end
