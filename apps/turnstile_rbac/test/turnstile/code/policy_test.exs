defmodule Turnstile.Code.PolicyTest do
  use ExUnit.Case, async: true

  alias Turnstile.Code.Conformance.Predicates
  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Code.Policy
  alias Turnstile.Code.Policy.Clause
  alias Turnstile.Code.Policy.Clauses
  alias Turnstile.Code.Policy.Object
  alias Turnstile.Code.Policy.Role
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

  defmodule Filters do
    @moduledoc false
    import Ecto.Query, only: [dynamic: 2]

    @spec open() :: Ecto.Query.dynamic_expr()
    def open, do: dynamic([folder], not is_nil(folder.name))
  end

  test "the role table is declared data" do
    assert Policy.roles(Roles) == [
             %Role{name: :reader, permissions: [:read]},
             %Role{name: :editor, permissions: [:read, :edit]}
           ]

    assert Policy.table(Roles) == [reader: [:read], editor: [:read, :edit]]
    assert Policy.operations(Roles) == [:read, :edit]
    assert Policy.roles_for(Roles, :read) == [:reader, :editor]
    assert Policy.roles_for(Roles, :edit) == [:editor]
    assert Policy.roles_for(Roles, :delete) == []
  end

  test "each protected schema carries its clauses in declaration order" do
    assert [%Object{schema: Folder, clauses: folder}, %Object{schema: Item, clauses: item}] = Policy.objects(Roles)

    assert [
             %Clause{name: :membership, kind: :grant, source: Membership, on: nil},
             %Clause{name: :cleared, kind: :predicate, predicate: predicate}
           ] = folder

    assert predicate == (&Predicates.cleared/2)
    assert [%Clause{name: :folder_membership, kind: :grant, on: :folder_id}, %Clause{name: :cleared}] = item
    assert Clauses.object_of(Roles, :item).schema == Item
    assert Clauses.object_of(Roles, :document) == nil
  end

  test "the rule modules are the policy and the predicate modules" do
    assert Policy.modules(Roles) == [Predicates, Roles]
    assert Policy.options(Roles) == [version: "conformance", author: "turnstile_rbac", approval: "the conformance suite"]
  end

  test "a predicate must be a capture of a named function" do
    assert_raise ArgumentError, ~r/capture of a named function/, fn ->
      Clauses.predicate(:anonymous, fn _subject, _environment -> true end, [])
    end

    assert %Clause{only: [:edit]} = Clauses.predicate(:cleared, &Predicates.cleared/2, only: [:edit])
  end

  test "a hop is a schema and a column, with a named filter when it has one" do
    assert %Clause{through: [{Folder, :id, []}]} =
             Clauses.grant(:hopped, Membership, on: :folder_id, through: [{Folder, :id}])

    assert %Clause{through: [{Folder, :id, where: filter}]} =
             Clauses.grant(:hopped, Membership, on: :folder_id, through: [{Folder, :id, where: &Filters.open/0}])

    assert filter == (&Filters.open/0)

    assert_raise NimbleOptions.ValidationError, ~r/named function of no arguments/, fn ->
      Clauses.grant(:hopped, Membership, through: [{Folder, :id, where: fn -> true end}])
    end

    assert_raise NimbleOptions.ValidationError, ~r/expected \{schema, column\}/, fn ->
      Clauses.grant(:hopped, Membership, through: [Folder])
    end
  end

  test "a grant needs the role column named when the relationship declares more than one attribute or none" do
    assert %Clause{as: :reader} = Clauses.grant(:fixed, Membership, as: :reader)
    assert_raise ArgumentError, ~r/declares no relationship/, fn -> Clauses.grant(:bare, Folder, []) end
    assert_raise ArgumentError, ~r/declares no object type/, fn -> Clauses.object(Membership, []) end
    assert_raise ArgumentError, ~r/permissions must be atoms/, fn -> Policy.__role__(:reader, ["read"]) end
  end
end
