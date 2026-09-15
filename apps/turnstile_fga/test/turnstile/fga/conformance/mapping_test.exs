defmodule Turnstile.Fga.Conformance.MappingTest do
  use Turnstile.Fga.TupleMappingCase,
    async: true,
    mapping: Turnstile.Fga.Conformance.Mapping,
    repo: Turnstile.TestRepos.Sandboxed,
    population: Turnstile.Fga.Conformance.Population,
    sandbox: Turnstile.Fga.Conformance.Setup

  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.TupleKey
  alias Turnstile.TestRepos.Sandboxed

  @cleared %Condition{
    name: "grant_holds",
    context: %{"clearance" => "cleared", "kind" => "user", "expires_at" => "9999-12-31T23:59:59Z"}
  }

  test "a role on a folder is the account holding it, under the condition its clearance, kind, and expiry carry" do
    tuples = Mapping.tuples(Sandboxed, "folder:1")

    assert %TupleKey{user: "user:acct-a", relation: "editor", object: "folder:1", condition: @cleared} in tuples
    assert %TupleKey{user: "user:acct-b", relation: "reader", object: "folder:1", condition: @cleared} in tuples
    assert length(tuples) == 2
  end

  test "a membership with an expiry and a kind carries both on its condition" do
    condition = Mapping.condition("cleared", :privileged, ~U[2999-01-01 00:00:00Z])

    assert condition.context == %{
             "clearance" => "cleared",
             "kind" => "privileged",
             "expires_at" => "2999-01-01T00:00:00Z"
           }
  end

  test "a membership whose account has no clearance states no tuple" do
    tuples = Mapping.tuples(Sandboxed, "folder:2")

    assert Enum.map(tuples, & &1.user) == ["user:acct-a"]
  end

  test "a clearance is an entity of its own, which every account of that clearance holds member on" do
    tuples = Mapping.tuples(Sandboxed, "clearance:cleared")

    assert Enum.map(tuples, & &1.user) == ["user:acct-a", "user:acct-b"]
    assert Enum.all?(tuples, &(&1.relation == "member" and &1.condition == nil))
  end

  test "a folder with no membership on it is an object of its type and requires nothing" do
    assert "folder:3" in Mapping.objects(Sandboxed, "folder")
    assert Mapping.tuples(Sandboxed, "folder:3") == []
  end
end
