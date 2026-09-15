defmodule ExampleFga.Infrastructure.TupleMapping do
  @moduledoc """
  The example's tables as tuples of the model in `priv/fga/model.fga`.

  What is here is the half that reads rows: which object types this
  application writes, which objects of a type its tables hold, which objects
  one change can have affected, and which rows an object's tuples are read
  from. What a row then states is `lib/example_fga/infrastructure/tuples.ex`, which
  reads nothing.

  Three shapes carry the whole translation. A role a row holds is a relation
  of the object it is held on: an assignment is `member` or `lead` on a
  program, and an office role is `designator` or `approver` on an office,
  read from the row's own account, office, and role, so an account holding
  both roles in one office holds both relations. A subject attribute is
  membership of its value as an object of its own, because a graph compares
  by walking rather than by equality: an account's nationality is `member` of
  a country and its employment is `member` of an employment. And a control
  that applies is the wildcard `user:*` on the relation named for it, so what
  a marking states is one fact about the document rather than a tuple per
  account.

  Decontrol is the condition `before_decontrol` on the tuples a decontrol
  date lapses: the controls a document or a portion carries, and the category
  those controls may be implied from. The date is the tuple's, the moment of
  the question is the context the adapter sends, and the comparison is the
  model's, so a date that passes needs no drain. A portion's tuples carry the
  document's date, because a portion is decontrolled with the document it
  belongs to and the column holding the date is the document's, which is why
  the mapping fetches that row and the translation is given the date.

  What an object requires is read from the rows as they stand, so an object
  whose rows are gone requires nothing and a drain of it takes its tuples
  away. A closed program is that shape rather than a case of its own: the row
  is there, the column names a moment, and the program then requires none of
  the assignment tuples it held.

  A change names more objects than the row it was made on. A date that
  decontrols a document changes what every portion of it requires, and a row
  that moved between two parents names the parent it left and the parent it
  joined, the first from the change and the second from the row.
  """

  @behaviour Turnstile.Fga.TupleMapping

  import Ecto.Query, only: [from: 2]

  alias Example.Domain.Agency
  alias Example.Domain.Assignment
  alias Example.Domain.Category
  alias Example.Domain.Document
  alias Example.Domain.Marking
  alias Example.Domain.Office
  alias Example.Domain.OfficeRole
  alias Example.Domain.Portion
  alias Example.Domain.Program
  alias Example.Domain.Proposal
  alias Example.Domain.User
  alias ExampleFga.Infrastructure.Tuples
  alias Turnstile.Fga.TupleMapping

  # The types tuples are written on. An account is `user`, which the model
  # gives no relation of its own, so nothing is written on one.
  @object_types ~w[agency office program category country employment document portion proposal]

  # An agency's own staff are the accounts in federal employment, which is
  # what FEDONLY clears.
  @federal "employment:federal"

  @exemption {:exempt, "tuple mapping: the rows an object's tuples are read from"}

  @impl TupleMapping
  def object_types, do: @object_types

  @impl TupleMapping
  def objects(repo, type), do: Tuples.named(type, ids(repo, type))

  @impl TupleMapping
  def changed(_repo, %{schema: User, changes: changes}) do
    Tuples.named("country", moved(changes, :nationality)) ++ Tuples.named("employment", moved(changes, :employment))
  end

  def changed(_repo, %{schema: Agency, target: {_kind, id}}), do: ["agency:#{id}"]

  def changed(_repo, %{schema: Office, target: {_kind, id}}), do: ["office:#{id}"]

  def changed(repo, %{schema: OfficeRole, target: {_kind, id}, changes: changes}) do
    Tuples.named("office", moved(changes, :office_id) ++ held(repo, OfficeRole, id, :office_id))
  end

  def changed(_repo, %{schema: Program, target: {_kind, id}}), do: ["program:#{id}"]

  def changed(repo, %{schema: Assignment, target: {_kind, id}, changes: changes}) do
    Tuples.named("program", moved(changes, :program_id) ++ held(repo, Assignment, id, :program_id))
  end

  def changed(_repo, %{schema: Category, target: {_kind, name}}), do: ["category:#{name}"]

  def changed(repo, %{schema: Document, target: {_kind, id}}) do
    ["document:#{id}" | of_document(repo, Portion, "portion", id) ++ of_document(repo, Proposal, "proposal", id)]
  end

  def changed(repo, %{schema: Marking, target: {_kind, id}}) do
    Tuples.named("document", held(repo, Marking, id, :document_id))
  end

  def changed(repo, %{schema: Portion, target: {_kind, id}, changes: changes}) do
    documents = moved(changes, :document_id) ++ held(repo, Portion, id, :document_id)

    ["portion:#{id}" | Tuples.named("document", documents)]
  end

  def changed(_repo, %{schema: Proposal, target: {_kind, id}}), do: ["proposal:#{id}"]

  def changed(_repo, %{}), do: []

  @impl TupleMapping
  def tuples(repo, object) do
    case String.split(object, ":", parts: 2) do
      [type, id] -> required(repo, type, id)
      _untyped -> []
    end
  end

  defp ids(repo, "agency"), do: all(repo, from(agency in Agency, select: agency.id))
  defp ids(repo, "office"), do: all(repo, from(office in Office, select: office.id))
  defp ids(repo, "program"), do: all(repo, from(program in Program, select: program.id))
  defp ids(repo, "category"), do: all(repo, from(category in Category, select: category.name))
  defp ids(repo, "country"), do: held_by_accounts(repo, :nationality)
  defp ids(repo, "employment"), do: held_by_accounts(repo, :employment)
  defp ids(repo, "document"), do: all(repo, from(document in Document, select: document.id))
  defp ids(repo, "portion"), do: all(repo, from(portion in Portion, select: portion.id))
  defp ids(repo, "proposal"), do: all(repo, from(proposal in Proposal, select: proposal.id))
  defp ids(_repo, _type), do: []

  # The values accounts hold in a subject attribute, each of which is an
  # object of its own. A value no account holds is an object nothing walks
  # to, so a country a marking releases to and no account belongs to is not
  # one of these.
  defp held_by_accounts(repo, :nationality) do
    all(repo, from(user in User, where: not is_nil(user.nationality), distinct: true, select: user.nationality))
  end

  defp held_by_accounts(repo, :employment) do
    all(repo, from(user in User, where: not is_nil(user.employment), distinct: true, select: user.employment))
  end

  defp required(repo, "agency", id), do: agency_tuples(repo, id)
  defp required(repo, "office", id), do: office_tuples(repo, id)
  defp required(repo, "program", id), do: program_tuples(repo, id)
  defp required(repo, "category", name), do: category_tuples(repo, name)
  defp required(repo, "country", value), do: country_tuples(repo, value)
  defp required(repo, "employment", value), do: employment_tuples(repo, value)
  defp required(repo, "document", id), do: document_tuples(repo, id)
  defp required(repo, "portion", id), do: portion_tuples(repo, id)
  defp required(repo, "proposal", id), do: proposal_tuples(repo, id)
  defp required(_repo, _type, _id), do: []

  # The agency's country and the employment its own staff hold. The
  # override permission is held outside any agency and outside the model,
  # so an agency requires nothing of the accounts holding it.
  defp agency_tuples(repo, id) do
    case row(repo, Agency, id) do
      %Agency{nationality: nationality} when is_binary(nationality) ->
        [
          Tuples.key("country:#{nationality}", "domestic", "agency:#{id}"),
          Tuples.key(@federal, "federal", "agency:#{id}")
        ]

      _absent ->
        []
    end
  end

  defp office_tuples(repo, id) do
    case row(repo, Office, id) do
      %Office{agency_id: nil} -> role_tuples(repo, id)
      %Office{agency_id: agency} -> [agency_link(agency, id) | role_tuples(repo, id)]
      nil -> []
    end
  end

  defp agency_link(agency, id), do: Tuples.key("agency:#{agency}", "agency", "office:#{id}")

  defp role_tuples(repo, id) do
    query =
      from(role in OfficeRole,
        where: role.office_id == ^id and not is_nil(role.role),
        distinct: true,
        select: {role.user_id, role.role}
      )

    Tuples.roles(all(repo, query), "office:#{id}")
  end

  # A closed program is a purpose that has ended, so it requires no tuple at
  # all and every assignment to it stops holding one.
  defp program_tuples(repo, id) do
    case row(repo, Program, id) do
      %Program{closed_at: nil} -> assignment_tuples(repo, id)
      _closed_or_absent -> []
    end
  end

  defp assignment_tuples(repo, id) do
    query =
      from(assignment in Assignment,
        where: assignment.program_id == ^id and not is_nil(assignment.role),
        distinct: true,
        select: {assignment.user_id, assignment.role}
      )

    Tuples.roles(all(repo, query), "program:#{id}")
  end

  # An unspecified category implies nothing, whatever its controls column
  # holds, which is what the specified flag decides.
  defp category_tuples(repo, name) do
    case row(repo, Category, name) do
      %Category{specified: true, implied_controls: controls} -> Tuples.implied(controls, "category:#{name}")
      _unspecified_or_absent -> []
    end
  end

  defp country_tuples(repo, value) do
    query = from(user in User, where: user.nationality == ^value, select: user.id)

    Tuples.members(all(repo, query), "country:#{value}")
  end

  # The employment column holds one of a fixed set, so a value outside that
  # set names no account and is asked about rather than queried for. The set
  # is read from the schema at run time, because a package reading it at
  # compile time would be recompiled whenever the example's tables change.
  defp employment_tuples(repo, value) do
    employments = Ecto.Enum.values(User, :employment)

    case Enum.find(employments, &(to_string(&1) == value)) do
      nil -> []
      employment -> employment_members(repo, employment, value)
    end
  end

  defp employment_members(repo, employment, value) do
    query = from(user in User, where: user.employment == ^employment, select: user.id)

    Tuples.members(all(repo, query), "employment:#{value}")
  end

  defp document_tuples(repo, id) do
    case row(repo, Document, id) do
      nil -> []
      %Document{} = document -> carried(repo, document, id, marking(repo, id))
    end
  end

  defp carried(repo, %Document{} = document, id, marking) do
    lapses = Tuples.lapsing(document.decontrol)

    structure_tuples(document, id) ++
      portion_links(repo, id) ++
      listed(marking, "document:#{id}") ++
      Tuples.marking(marking, "document:#{id}", lapses)
  end

  defp listed(nil, _object), do: []
  defp listed(%Marking{list: list}, object), do: Tuples.listed(list, object)

  # What a walk reaches the rules through: the program a document belongs to
  # and the office that designated it.
  defp structure_tuples(%Document{} = document, id) do
    links = [
      {document.program_id, "program", "program"},
      {document.designating_office_id, "office", "designating_office"}
    ]

    for {value, type, relation} <- links, value, do: Tuples.key("#{type}:#{value}", relation, "document:#{id}")
  end

  defp portion_links(repo, id) do
    query = from(portion in Portion, where: portion.document_id == ^id, select: portion.id)

    for portion <- all(repo, query), do: Tuples.key("portion:#{portion}", "portion", "document:#{id}")
  end

  defp portion_tuples(repo, id) do
    case row(repo, Portion, id) do
      %Portion{document_id: nil} ->
        []

      %Portion{document_id: document} = portion ->
        [
          Tuples.key("document:#{document}", "document", "portion:#{id}")
          | Tuples.marking(portion, "portion:#{id}", decontrol_of(repo, document))
        ]

      nil ->
        []
    end
  end

  # The office that may approve, reached through the document the proposal is
  # about, and the account that proposed, which the model subtracts.
  defp proposal_tuples(repo, id) do
    case row(repo, Proposal, id) do
      nil -> []
      %Proposal{} = proposal -> office_link(repo, id, proposal.document_id) ++ proposer_link(id, proposal.proposer_id)
    end
  end

  defp office_link(_repo, _id, nil), do: []

  defp office_link(repo, id, document) do
    case row(repo, Document, document) do
      %Document{designating_office_id: nil} ->
        []

      %Document{designating_office_id: office} ->
        [Tuples.key("office:#{office}", "office", "proposal:#{id}")]

      nil ->
        []
    end
  end

  defp proposer_link(_id, nil), do: []

  defp proposer_link(id, proposer), do: [Tuples.key("user:#{proposer}", "proposer", "proposal:#{id}")]

  defp marking(repo, id) do
    query = from(marking in Marking, where: marking.document_id == ^id)

    repo.one(query, turnstile: @exemption)
  end

  defp decontrol_of(repo, document) do
    case row(repo, Document, document) do
      nil -> nil
      %Document{decontrol: at} -> Tuples.lapsing(at)
    end
  end

  # The rows that name the document, which is how a date on the document
  # reaches its portions and a change of office reaches its proposals.
  defp of_document(repo, Portion, type, id) do
    Tuples.named(type, all(repo, from(portion in Portion, where: portion.document_id == ^id, select: portion.id)))
  end

  defp of_document(repo, Proposal, type, id) do
    Tuples.named(type, all(repo, from(proposal in Proposal, where: proposal.document_id == ^id, select: proposal.id)))
  end

  # The column as the row holds it now, for a change that left it alone: a
  # delete carries its own in the change, and a row that is gone answers
  # nothing here.
  defp held(repo, schema, id, column) do
    case row(repo, schema, id) do
      nil -> []
      found -> Enum.reject([Map.fetch!(found, column)], &is_nil/1)
    end
  end

  defp moved(changes, column) do
    case Map.fetch(changes, column) do
      {:ok, {was, now}} -> Enum.reject([was, now], &is_nil/1)
      :error -> []
    end
  end

  defp row(repo, schema, id), do: repo.get(schema, id, turnstile: @exemption)

  defp all(repo, query), do: repo.all(query, turnstile: @exemption)
end
