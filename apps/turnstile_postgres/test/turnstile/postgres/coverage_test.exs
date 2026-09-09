defmodule Turnstile.Postgres.CoverageTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Coverage
  alias Turnstile.Postgres.Probe
  alias Turnstile.TestRepos.Sandboxed

  setup do
    Sandbox.checkout(Sandboxed)
  end

  test "every column the conformance policies read is a declared fact" do
    binding = binding!([Account, Folder, Item, Membership])
    assert Coverage.check(binding) == :ok
    assert Coverage.check!(binding) == :ok
  end

  test "a policy that reads an undeclared column fails with the column's name" do
    binding = binding!([Probe.Row])

    assert {:error, findings} = Coverage.check(binding)
    assert {Probe.Row, "label"} in findings

    assert_raise ArgumentError, ~r/label of Turnstile.Postgres.Probe.Row/, fn -> Coverage.check!(binding) end
  end

  test "a policy that reads a table no bound schema names fails as that table" do
    assert {:table, "turnstile_fixture_accounts"} in Coverage.undeclared(binding!([Probe.Row]))
  end

  test "the foreign key of a carried relation is declared on the schema that holds it" do
    assert {Item, "folder_id"} in Coverage.undeclared(binding!([Item]))
    refute {Item, "folder_id"} in Coverage.undeclared(binding!([Folder, Item]))
  end

  defp binding!(schemas) do
    {:ok, binding} = Binding.new(repo: Sandboxed, schemas: schemas)
    binding
  end
end
