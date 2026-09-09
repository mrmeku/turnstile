defmodule Turnstile.Fga.Conformance do
  @moduledoc """
  The conformance artifact of this adapter: the tuple mapping for the neutral
  fixture, which is what turns that fixture's fact events into tuples. The
  model those tuples are read under sits beside this file as its own text,
  which is what the server reads. The test run compiles the module; an
  application never loads it.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Fga], exports: [Mapping]
end

defmodule Turnstile.Fga.Conformance.Mapping do
  @moduledoc """
  The neutral fixture as tuples. A membership of an account on a folder is
  the account holding the membership's role on that folder, and an account's
  clearance is the account holding `member` on the clearance as an entity of
  its own, because a graph compares by walking rather than by equality.

  A folder tuple carries the account's clearance as the condition
  `while_cleared`, so a clearance that changes is the same tuple key with
  another value on it: the drain deletes that tuple and writes it again, in
  two calls. That is the shape a control with a parameter has, in the
  fixture's own terms.

  The objects a clearance event touches are read from the fold: the
  clearances it moved between, which the event names, and every folder the
  account holds a membership on, which it does not.
  """

  @behaviour Turnstile.Fga.TupleMapping

  alias Turnstile.FactEvent
  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Ledger.Fold

  @condition "while_cleared"

  @impl Turnstile.Fga.TupleMapping
  def object_types, do: ["clearance", "folder"]

  @impl Turnstile.Fga.TupleMapping
  def touched(%Fold{}, %FactEvent{kind: :relationship, object_ref: {:folder, id}}), do: ["folder:#{id}"]

  def touched(%Fold{} = fold, %FactEvent{kind: :subject_attribute, attribute: :clearance} = event) do
    {:user, account} = event.subject_ref

    Enum.sort(folders(fold, account) ++ clearances([event.old, event.new]))
  end

  def touched(%Fold{}, %FactEvent{}), do: []

  @impl Turnstile.Fga.TupleMapping
  def tuples(%Fold{} = fold, object) do
    case String.split(object, ":", parts: 2) do
      ["folder", id] -> folder_tuples(fold, id)
      ["clearance", value] -> clearance_tuples(fold, value)
      _other -> []
    end
  end

  defp folder_tuples(%Fold{} = fold, id) do
    for {{{:user, account}, {:folder, folder}, nil}, value} <- fold.facts,
        to_string(folder) == id,
        role = role(value) do
      %TupleKey{
        user: "user:#{account}",
        relation: Atom.to_string(role),
        object: "folder:#{id}",
        condition: condition(clearance(fold, account))
      }
    end
  end

  defp clearance_tuples(%Fold{} = fold, value) do
    for {{{:user, account}, nil, :clearance}, ^value} <- fold.facts do
      %TupleKey{user: "user:#{account}", relation: "member", object: "clearance:#{value}"}
    end
  end

  # A relationship's fact is the role itself for one attribute and a map of
  # them for several, and a role of nothing states no tuple.
  defp role(%{role: role}), do: role
  defp role(role) when is_atom(role), do: role
  defp role(_other), do: nil

  defp clearance(%Fold{facts: facts}, account), do: Map.get(facts, {{:user, account}, nil, :clearance})

  defp condition(nil), do: nil
  defp condition(clearance), do: %Condition{name: @condition, context: %{"clearance" => clearance}}

  defp folders(%Fold{facts: facts}, account) do
    for {{{:user, ^account}, {:folder, folder}, nil}, _value} <- facts, do: "folder:#{folder}"
  end

  defp clearances(values) do
    for value <- values, is_binary(value), do: "clearance:#{value}"
  end
end
