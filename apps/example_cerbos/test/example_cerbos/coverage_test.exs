defmodule ExampleCerbos.CoverageTest do
  @moduledoc """
  Declared-fact coverage (`docs/reference.md` §14) over the CUI policies:
  every column the rules of this binding read is a declared fact of the
  example.

  The rules reach the database as the `dynamic` a scope answers with, so the
  case asks for that `dynamic` for every account and every object type a
  scope is taken over, walks it with the subqueries the attribute
  declarations named inside it, and sets each field reference against the
  declarations of the schema it belongs to. A column no declaration covers
  fails the case with the column's name, because a decision that depended on
  it would replay from a ledger that never recorded it.
  """

  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Example.Assignment
  alias Example.Category
  alias Example.Document
  alias Example.Fixture
  alias Example.Marking
  alias Example.OfficeRole
  alias Example.Portion
  alias ExampleCerbos.Attributes
  alias Turnstile.Cerbos.Coverage
  alias Turnstile.Test.Sandbox

  @scopes [{:read, :document, Document}, {:set_decontrol, :document, Document}, {:read, :portion, Portion}]

  setup tags do
    :ok = Sandbox.setup(Example.Repo, tags)
    world = Fixture.world!()

    document =
      Fixture.document!(world,
        categories: ["PRVCY"],
        controls: [:federal_only, :no_foreign, :named_list, :releasable_to],
        releasable_to: ["US"],
        list: ["ann"],
        portions: [%{body: "open"}, %{body: "federal", controls: [:federal_only]}]
      )

    {:ok, world: world, document: document}
  end

  test "every column the rule of a scope reads is a declared fact" do
    for subject <- Fixture.subjects(), {operation, kind, schema} <- @scopes do
      {rule, _decision} = Turnstile.scope(subject, operation, kind, fresh())
      query = from(row in schema, where: ^rule)

      assert Coverage.check(Attributes, query) == :ok,
             "#{subject.id} #{operation} #{kind} reads #{inspect(Coverage.undeclared(Attributes, query))}"
    end
  end

  test "the walk reaches the columns the declared subqueries read" do
    {rule, _decision} = Turnstile.scope(Fixture.subject("bob"), :read, :document, fresh())
    query = from(d in Document, where: ^rule)
    reads = Coverage.reads(query)

    assert {Assignment, :role} in reads
    assert {OfficeRole, :role} in reads
    assert {Marking, :controls} in reads
    assert {Category, :implied_controls} in reads
    assert {Document, :decontrol} in reads
  end

  test "a column no declaration covers fails the case with the column's name" do
    query = from(d in Document, where: d.title == "document")

    assert Coverage.check(Attributes, query) == {:error, [{Document, :title}]}
    assert_raise ArgumentError, ~r/title of Example.Document/, fn -> Coverage.check!(Attributes, query) end
  end

  defp fresh, do: [facts: %{reauthenticated_at: DateTime.utc_now()}]
end
