defmodule Turnstile.Code.PolicyTest do
  use ExUnit.Case, async: true

  alias Turnstile.Code.Conformance.Predicates
  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Code.Policy
  alias Turnstile.Code.Policy.Clause
  alias Turnstile.Code.Policy.Object
  alias Turnstile.Code.Policy.Role
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership

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
    assert Policy.object_of(Roles, :item).schema == Item
    assert Policy.object_of(Roles, :document) == nil
  end

  test "the rule modules are the policy and the predicate modules" do
    assert Policy.modules(Roles) == [Predicates, Roles]
    assert Policy.options(Roles) == [version: "conformance", author: "turnstile_rbac", approval: "the conformance suite"]
  end

  test "a predicate must be a capture of a named function" do
    assert_raise ArgumentError, ~r/capture of a named function/, fn ->
      Policy.__predicate__(:anonymous, fn _subject, _environment -> true end)
    end
  end

  test "a grant needs the role column named when the relationship declares more than one attribute or none" do
    assert %Clause{as: :reader} = Policy.__grant__(:fixed, Membership, as: :reader)
    assert_raise ArgumentError, ~r/declares no relationship/, fn -> Policy.__grant__(:bare, Folder, []) end
    assert_raise ArgumentError, ~r/declares no object type/, fn -> Policy.__object__(Membership, []) end
    assert_raise ArgumentError, ~r/permissions must be atoms/, fn -> Policy.__role__(:reader, ["read"]) end
  end
end
