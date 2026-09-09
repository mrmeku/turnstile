defmodule Turnstile.Cerbos.CoverageTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Conformance.Attributes
  alias Turnstile.Cerbos.Coverage
  alias Turnstile.Cerbos.Decide
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Fixture.World
  alias Turnstile.Scope
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    sidecar = Test.Cerbos.info()
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = Test.with_config(adapter: {Turnstile.Cerbos, address: sidecar.address}, ledger: :none)

    :ok =
      Binding.override(repo: Sandboxed, attributes: Attributes, policies: sidecar.policies, commit: "conformance")

    world = %World{
      accounts: %{"ann" => World.cleared()},
      folders: [1],
      items: %{10 => 1},
      memberships: %{{"ann", 1} => :reader}
    }

    :ok = World.insert(Sandboxed, world)
    {:ok, binding} = Binding.resolve()
    {:ok, binding: binding, address: sidecar.address, ann: %Subject{id: "ann", kind: :user}}
  end

  test "the query the sidecar's own plan compiles to reads declared facts alone", ctx do
    assert {:ok, %Scope{} = folders} = Decide.scoped(ctx.binding, ctx.address, ctx.ann, :read, :folder)
    assert Coverage.check(Attributes, from(f in Folder, where: ^folders.rule)) == :ok

    assert {:ok, %Scope{} = items} = Decide.scoped(ctx.binding, ctx.address, ctx.ann, :edit, :item)
    assert Coverage.check!(Attributes, from(i in Item, where: ^items.rule)) == :ok
  end

  test "a column no declaration covers is a finding naming the schema" do
    assert Coverage.check(Attributes, from(f in Folder, where: f.name == "folder 1")) == {:error, [{Folder, :name}]}

    assert_raise ArgumentError, ~r/name of Turnstile.Fixture.Folder/, fn ->
      Coverage.check!(Attributes, from(f in Folder, where: f.name == "folder 1"))
    end
  end

  test "a fragment cannot be walked, so it is a finding" do
    query = from(f in Folder, where: fragment("? = 'folder 1'", f.name))

    assert Coverage.check(Attributes, query) == {:error, [{:fragment, "? = 'folder 1'"}]}
    assert_raise ArgumentError, ~r/fragment "\? = 'folder 1'"/, fn -> Coverage.check!(Attributes, query) end
  end

  test "the walk follows a subquery, and the relationship's own columns are declared" do
    members = from(m in Membership, where: m.account_id == "ann" and m.role == :reader, select: m.folder_id)
    query = from(f in Folder, where: f.id in subquery(members))

    assert Coverage.check(Attributes, query) == :ok
    reads = Coverage.reads(query)
    assert {Membership, :account_id} in reads
    assert {Membership, :role} in reads
    assert {Folder, :id} in reads
  end

  test "the foreign key of a carried relation is declared on the schema that holds it" do
    assert Coverage.check(Attributes, from(i in Item, where: not is_nil(i.folder_id))) == :ok
  end

  test "a field of a source that is no schema is covered by the walk of that source" do
    members = from(m in Membership, select: %{folder: m.folder_id})

    assert Coverage.check(Attributes, from(s in subquery(members), where: s.folder > 0)) == :ok
  end

  test "the walk reads every clause of a query, not the filter alone" do
    query =
      from(f in Folder,
        join: m in Membership,
        on: m.folder_id == f.id,
        where: m.account_id == "ann",
        group_by: f.name,
        having: count(m.id) > 0,
        order_by: f.name,
        select: f.name
      )

    assert Coverage.check(Attributes, query) == {:error, [{Folder, :name}]}
  end
end
