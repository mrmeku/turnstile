defmodule Turnstile.Cerbos.ValuesTest do
  use ExUnit.Case, async: true

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Conformance.Memberships
  alias Turnstile.Cerbos.Values
  alias Turnstile.Environment
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership
  alias Turnstile.Fixture.World
  alias Turnstile.Object
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  defmodule Pair do
    @moduledoc false
    use Ecto.Schema

    @primary_key false

    @type t :: %__MODULE__{}

    schema "turnstile_cerbos_values_test_pairs" do
      field(:left, :string, primary_key: true)
      field(:right, :string, primary_key: true)
    end
  end

  defmodule Declarations do
    @moduledoc false
    use Turnstile.Cerbos.Attributes

    principal :user, schema: Account do
      attribute :clearance, column: :clearance
    end

    resource :folder, schema: Folder do
      attribute :name, column: :name
      attribute :member_roles, subquery: &Memberships.folder_roles_for/1
    end

    resource :membership, schema: Membership do
      attribute :role, column: :role
    end

    resource :pair, schema: Pair do
      attribute :left, column: :left
    end

    environment do
      fact(:reauthenticated_at)
    end
  end

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = Test.with_config(adapter: {Turnstile.Cerbos, address: Test.Cerbos.info().address}, ledger: :none)

    :ok =
      Binding.override(
        repo: Sandboxed,
        attributes: Declarations,
        policies: "priv/conformance",
        commit: "conformance"
      )

    world = %World{
      accounts: %{"ann" => World.cleared(), "bob" => nil},
      folders: [1, 2],
      items: %{},
      memberships: %{{"ann", 1} => :reader}
    }

    :ok = World.insert(Sandboxed, world)
    {:ok, binding} = Binding.resolve()

    {:ok,
     binding: binding,
     ann: %Subject{id: "ann", kind: :user},
     bob: %Subject{id: "bob", kind: :user},
     request: %Environment{now: ~U[2026-09-09 12:00:00.123456Z]}}
  end

  test "the subject's own attributes come from the row its id names, the request's facts beside them", ctx do
    facts = %{now: "2026-09-09T12:00:00Z", reauthenticated_at: nil}

    assert Values.principal(ctx.binding, ctx.ann, ctx.request) ==
             {:ok, %{clearance: "cleared", environment: facts}}

    assert Values.principal(ctx.binding, ctx.bob, ctx.request) == {:ok, %{clearance: nil, environment: facts}}
  end

  test "a fact the declarations name travels cut to the second, and one they do not name does not", ctx do
    request = %Environment{
      now: ~U[2026-09-09 12:00:00Z],
      facts: %{reauthenticated_at: ~U[2026-09-09 11:59:30.987654Z], clearance: "cleared"}
    }

    assert Values.environment(ctx.binding, request) == %{
             now: "2026-09-09T12:00:00Z",
             reauthenticated_at: "2026-09-09T11:59:30Z"
           }
  end

  test "an object's attributes are its columns and what the subject's subquery selected for it", ctx do
    objects = [%Object{type: :folder, id: 1}, %Object{type: :folder, id: 2}]

    assert {:ok, by_id} = Values.resources(ctx.binding, ctx.ann, :folder, objects)
    assert by_id["1"] == %{name: "folder 1", member_roles: ["reader"]}
    assert by_id["2"] == %{name: "folder 2", member_roles: []}

    assert {:ok, for_bob} = Values.resources(ctx.binding, ctx.bob, :folder, objects)
    assert for_bob["1"] == %{name: "folder 1", member_roles: []}
  end

  test "an id no row holds carries every declared attribute as absent", ctx do
    assert {:ok, by_id} = Values.of(ctx.binding, ctx.ann, :folder, [99])
    assert by_id["99"] == %{name: nil, member_roles: []}
  end

  test "a column the row holds as an atom reaches the sidecar as the text the column holds", ctx do
    [%Membership{id: id}] = Sandboxed.all(Membership, turnstile: World.exemption())

    assert {:ok, by_id} = Values.of(ctx.binding, ctx.ann, :membership, [id])
    assert by_id[to_string(id)] == %{role: "reader"}
  end

  test "a kind whose schema has no single primary key has no column an identifier names", ctx do
    assert Values.of(ctx.binding, ctx.ann, :pair, ["left"]) ==
             {:error, "the declarations name no schema with one primary key for pair"}
  end

  test "a value the query cannot cast is a failure the caller turns into a denial", ctx do
    assert {:error, detail} = Values.of(ctx.binding, ctx.ann, :folder, ["not an identifier"])
    assert detail =~ "not an identifier"
  end
end
