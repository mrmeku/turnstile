defmodule ExampleFga.TupleMapping do
  @moduledoc """
  The example's fact events as tuples of the model in `priv/fga/model.fga`.

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
  belongs to and the column holding the date is the document's.

  Two facts share one key, since a fold keys a relationship by its subject
  and its object alone: an account on a document's list, and the proposer of
  a marking change on the document proposed for. The value tells them apart,
  the list's being the account and the proposal's being its status, and an
  element removed leaves the key with nothing on it.

  The objects an event touched are read from the fold as well as from the
  event. A date that decontrols a document changes what every portion of it
  requires, an account granted the override permission is an operator of
  every agency, and a program that closes ends every assignment to it: the
  fold knows those objects and the event does not name them.
  """

  @behaviour Turnstile.Fga.TupleMapping

  alias Turnstile.FactEvent
  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fga.TupleMapping
  alias Turnstile.Ledger.Fold

  # The types tuples are written on. An account is `user`, which the model
  # gives no relation of its own, so nothing is written on one.
  @object_types ~w[agency office program category country employment document portion proposal]

  @condition "before_decontrol"

  # A control that applies, as the relation the model names for it.
  @applies %{
    federal_only: "fedonly_applies",
    no_foreign: "noforn_applies",
    releasable_to: "relto_applies",
    named_list: "list_applies"
  }

  # A category implies FEDONLY or NOFORN and neither of the other two: REL TO
  # rests on the countries a marking names and DL ONLY on the accounts it
  # lists, which a category carries neither of.
  @implied %{federal_only: "fedonly_applies", no_foreign: "noforn_applies"}

  # An agency's own staff are the accounts in federal employment, which is
  # what FEDONLY clears.
  @federal "employment:federal"

  @impl TupleMapping
  def object_types, do: @object_types

  @impl TupleMapping
  def touched(%Fold{}, %FactEvent{object_ref: nil, attribute: :nationality} = event) do
    named_each("country", [event.old, event.new])
  end

  def touched(%Fold{}, %FactEvent{object_ref: nil, attribute: :employment} = event) do
    named_each("employment", [event.old, event.new])
  end

  def touched(%Fold{} = fold, %FactEvent{object_ref: nil, attribute: :role}), do: agencies(fold)

  def touched(%Fold{} = fold, %FactEvent{object_ref: {:office_role, row}} = event) do
    Enum.uniq(offices_named(event) ++ office_of(fold, row))
  end

  def touched(%Fold{}, %FactEvent{object_ref: {:agency, id}}), do: ["agency:#{id}"]

  def touched(%Fold{}, %FactEvent{object_ref: {:office, id}}), do: ["office:#{id}"]

  def touched(%Fold{}, %FactEvent{object_ref: {:program, id}}), do: ["program:#{id}"]

  def touched(%Fold{}, %FactEvent{object_ref: {:category, id}}), do: ["category:#{id}"]

  def touched(%Fold{} = fold, %FactEvent{object_ref: {:document, id}, attribute: :decontrol}) do
    ["document:#{id}" | of_document(fold, :portion, id)]
  end

  def touched(%Fold{} = fold, %FactEvent{object_ref: {:document, id}, attribute: attribute})
      when attribute in [:program_id, :designating_office_id] do
    ["document:#{id}" | of_document(fold, :proposal, id)]
  end

  def touched(%Fold{}, %FactEvent{object_ref: {:document, id}}), do: ["document:#{id}"]

  def touched(%Fold{}, %FactEvent{object_ref: {:portion, id}, attribute: :document_id} = event) do
    ["portion:#{id}" | named_each("document", [event.old, event.new])]
  end

  def touched(%Fold{}, %FactEvent{object_ref: {:portion, id}}), do: ["portion:#{id}"]

  def touched(%Fold{}, %FactEvent{object_ref: {:proposal, id}}), do: ["proposal:#{id}"]

  def touched(%Fold{}, %FactEvent{}), do: []

  @impl TupleMapping
  def tuples(%Fold{} = fold, object) do
    case String.split(object, ":", parts: 2) do
      [type, id] -> required(fold, type, id)
      _untyped -> []
    end
  end

  defp required(fold, "agency", id), do: agency_tuples(fold, id)
  defp required(fold, "office", id), do: office_tuples(fold, id)
  defp required(fold, "program", id), do: program_tuples(fold, id)
  defp required(fold, "category", id), do: category_tuples(fold, id)
  defp required(fold, "country", id), do: country_tuples(fold, id)
  defp required(fold, "employment", id), do: employment_tuples(fold, id)
  defp required(fold, "document", id), do: document_tuples(fold, id)
  defp required(fold, "portion", id), do: portion_tuples(fold, id)
  defp required(fold, "proposal", id), do: proposal_tuples(fold, id)
  defp required(_fold, _type, _id), do: []

  # The agency's country, the employment its own staff hold, and the accounts
  # holding the override permission, which is held outside any agency and so
  # is an operator of each of them. All of it rests on the agency's own row,
  # which the fold knows by its nationality.
  defp agency_tuples(%Fold{} = fold, id) do
    case attribute(fold, :agency, id, :nationality) do
      nil ->
        []

      nationality ->
        [
          %TupleKey{user: "country:#{nationality}", relation: "domestic", object: "agency:#{id}"},
          %TupleKey{user: @federal, relation: "federal", object: "agency:#{id}"}
          | operator_tuples(fold, id)
        ]
    end
  end

  defp operator_tuples(%Fold{facts: facts}, id) do
    for {{{:user, account}, nil, :role}, :override} <- facts do
      %TupleKey{user: "user:#{account}", relation: "operator", object: "agency:#{id}"}
    end
  end

  defp office_tuples(%Fold{} = fold, id) do
    case attribute(fold, :office, id, :agency_id) do
      nil -> role_tuples(fold, id)
      agency -> [agency_link(agency, id) | role_tuples(fold, id)]
    end
  end

  defp agency_link(agency, id) do
    %TupleKey{user: "agency:#{agency}", relation: "agency", object: "office:#{id}"}
  end

  # One tuple per office-role row, so an account holding the designator role
  # and the approver role in one office holds both relations.
  defp role_tuples(%Fold{facts: facts} = fold, id) do
    for {{nil, {:office_role, row}, :office_id}, office} <- facts,
        to_string(office) == id,
        account = attribute(fold, :office_role, to_string(row), :user_id),
        role = attribute(fold, :office_role, to_string(row), :role) do
      %TupleKey{user: "user:#{account}", relation: Atom.to_string(role), object: "office:#{id}"}
    end
  end

  # A closed program is a purpose that has ended, so it requires no tuple at
  # all and every assignment to it stops holding one.
  defp program_tuples(%Fold{} = fold, id) do
    case attribute(fold, :program, id, :closed_at) do
      nil -> assignment_tuples(fold, id)
      %DateTime{} -> []
    end
  end

  defp assignment_tuples(%Fold{facts: facts}, id) do
    for {{{:user, account}, {:program, program}, nil}, role} <- facts,
        to_string(program) == id,
        role in [:lead, :member] do
      %TupleKey{user: "user:#{account}", relation: Atom.to_string(role), object: "program:#{id}"}
    end
  end

  # An unspecified category implies nothing, whatever its controls column
  # holds, which is what the specified flag decides.
  defp category_tuples(%Fold{} = fold, id) do
    case attribute(fold, :category, id, :specified) do
      true -> implied_tuples(fold, id)
      _unspecified -> []
    end
  end

  defp implied_tuples(%Fold{facts: facts}, id) do
    for {{{:control, control}, {:category, category}, :implied_controls}, _element} <- facts,
        to_string(category) == id,
        relation = @implied[control] do
      %TupleKey{user: "user:*", relation: relation, object: "category:#{id}"}
    end
  end

  defp country_tuples(%Fold{facts: facts}, id) do
    for {{{:user, account}, nil, :nationality}, ^id} <- facts do
      %TupleKey{user: "user:#{account}", relation: "member", object: "country:#{id}"}
    end
  end

  defp employment_tuples(%Fold{facts: facts}, id) do
    for {{{:user, account}, nil, :employment}, employment} <- facts, to_string(employment) == id do
      %TupleKey{user: "user:#{account}", relation: "member", object: "employment:#{id}"}
    end
  end

  defp document_tuples(%Fold{} = fold, id) do
    lapses = condition(attribute(fold, :document, id, :decontrol))

    structure_tuples(fold, id) ++
      portion_links(fold, id) ++
      listed_tuples(fold, id) ++
      marking_tuples(fold, {:document, id}, lapses)
  end

  # What a walk reaches the rules through: the program a document belongs to
  # and the office that designated it.
  defp structure_tuples(%Fold{} = fold, id) do
    links = [
      {attribute(fold, :document, id, :program_id), "program", "program"},
      {attribute(fold, :document, id, :designating_office_id), "office", "designating_office"}
    ]

    for {value, type, relation} <- links, value do
      %TupleKey{user: "#{type}:#{value}", relation: relation, object: "document:#{id}"}
    end
  end

  defp portion_links(%Fold{facts: facts}, id) do
    for {{nil, {:portion, portion}, :document_id}, document} <- facts, to_string(document) == id do
      %TupleKey{user: "portion:#{portion}", relation: "portion", object: "document:#{id}"}
    end
  end

  # The accounts a DL ONLY list names. The proposer of a marking change keys
  # the same way, and what tells the two apart is the value: the list's is the
  # account, the proposal's is its status, and a removal leaves nothing.
  defp listed_tuples(%Fold{facts: facts}, id) do
    for {{{:user, account}, {:document, document}, nil}, listed} <- facts,
        to_string(document) == id,
        is_binary(listed) do
      %TupleKey{user: "user:#{account}", relation: "listed", object: "document:#{id}"}
    end
  end

  defp portion_tuples(%Fold{} = fold, id) do
    case attribute(fold, :portion, id, :document_id) do
      nil ->
        []

      document ->
        [
          %TupleKey{user: "document:#{document}", relation: "document", object: "portion:#{id}"}
          | marking_tuples(fold, {:portion, id}, decontrol_of(fold, document))
        ]
    end
  end

  # A marking on a document or on a portion states the same three things,
  # keyed on the row that carries it: the categories it names, the countries
  # REL TO releases to, and the controls that apply.
  defp marking_tuples(%Fold{} = fold, marked, lapses) do
    category_links(fold, marked, lapses) ++ release_links(fold, marked) ++ control_flags(fold, marked, lapses)
  end

  defp category_links(%Fold{facts: facts}, {type, id}, lapses) do
    for {{{:category, category}, {^type, marked}, :categories}, _element} <- facts, to_string(marked) == id do
      %TupleKey{user: "category:#{category}", relation: "category", object: "#{type}:#{id}", condition: lapses}
    end
  end

  defp release_links(%Fold{facts: facts}, {type, id}) do
    for {{{:country, country}, {^type, marked}, :releasable_to}, _element} <- facts, to_string(marked) == id do
      %TupleKey{user: "country:#{country}", relation: "releasable_to", object: "#{type}:#{id}"}
    end
  end

  defp control_flags(%Fold{facts: facts}, {type, id}, lapses) do
    for {{{:control, control}, {^type, marked}, :controls}, _element} <- facts,
        to_string(marked) == id,
        relation = @applies[control] do
      %TupleKey{user: "user:*", relation: relation, object: "#{type}:#{id}", condition: lapses}
    end
  end

  # The office that may approve, reached through the document the proposal is
  # about, and the account that proposed, which the model subtracts.
  defp proposal_tuples(%Fold{} = fold, id) do
    office_link(fold, id, attribute(fold, :proposal, id, :document_id)) ++
      proposer_link(id, attribute(fold, :proposal, id, :proposer_id))
  end

  defp office_link(%Fold{}, _id, nil), do: []

  defp office_link(%Fold{} = fold, id, document) do
    case attribute(fold, :document, to_string(document), :designating_office_id) do
      nil -> []
      office -> [%TupleKey{user: "office:#{office}", relation: "office", object: "proposal:#{id}"}]
    end
  end

  defp proposer_link(_id, nil), do: []

  defp proposer_link(id, proposer) do
    [%TupleKey{user: "user:#{proposer}", relation: "proposer", object: "proposal:#{id}"}]
  end

  # The value of one object attribute, found by the identifier as the store
  # writes it, since a fold keys an object by the value its column holds.
  defp attribute(%Fold{facts: facts}, type, id, attribute) do
    Enum.find_value(facts, fn
      {{nil, {^type, object}, ^attribute}, value} -> if to_string(object) == id, do: value
      _other -> nil
    end)
  end

  defp condition(nil), do: nil

  defp condition(%DateTime{} = at) do
    %Condition{name: @condition, context: %{"decontrol_at" => DateTime.to_iso8601(at)}}
  end

  defp decontrol_of(%Fold{} = fold, document) do
    condition(attribute(fold, :document, to_string(document), :decontrol))
  end

  defp agencies(%Fold{facts: facts}) do
    for {{nil, {:agency, id}, :nationality}, _nationality} <- facts, do: "agency:#{id}"
  end

  # The rows of a type that name the document, which is how a date on the
  # document reaches its portions and a change of office reaches its
  # proposals.
  defp of_document(%Fold{facts: facts}, type, id) do
    for {{nil, {^type, row}, :document_id}, document} <- facts,
        to_string(document) == to_string(id),
        do: "#{type}:#{row}"
  end

  # The office an office-role event names, which a row being removed carries
  # as what it held.
  defp offices_named(%FactEvent{attribute: :office_id} = event), do: named_each("office", [event.old, event.new])
  defp offices_named(%FactEvent{}), do: []

  defp office_of(%Fold{} = fold, row) do
    named_each("office", [attribute(fold, :office_role, to_string(row), :office_id)])
  end

  defp named_each(type, values), do: for(value <- values, value, do: "#{type}:#{value}")
end
