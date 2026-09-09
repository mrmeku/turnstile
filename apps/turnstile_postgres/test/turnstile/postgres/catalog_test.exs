defmodule Turnstile.Postgres.CatalogTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Conformance.Rules
  alias Turnstile.Postgres.Policy
  alias Turnstile.Postgres.Probe
  alias Turnstile.TestRepos.Sandboxed

  setup do
    Sandbox.checkout(Sandboxed)
  end

  test "the catalog is the version, the policies of the bound tables, and the columns they read" do
    catalog = Catalog.read!(binding!())

    assert catalog.version == to_string(Rules.version())
    assert {"turnstile_fixture_folders", "id"} in catalog.columns
    assert {"turnstile_fixture_memberships", "role"} in catalog.columns

    written =
      catalog.policies
      |> Enum.map(& &1.name)
      |> Enum.uniq()
      |> Enum.sort()

    assert written == names()
  end

  test "a scope policy and a gate policy are found by the operation they were written for" do
    catalog = Catalog.read!(binding!())

    assert %Policy{command: :select, using: using} = Catalog.scope(catalog, "turnstile_fixture_folders", :read)
    assert using =~ "'read'::text"
    assert %Policy{command: :update} = Catalog.gate(catalog, "turnstile_fixture_folders", :edit)
    assert Catalog.gate(catalog, "turnstile_fixture_items", :edit) == nil
    assert Catalog.scope(catalog, "turnstile_fixture_folders", :publish) == nil
  end

  test "the text a version carries names the table, the policy, the command, and both expressions" do
    catalog = Catalog.read!(binding!())
    text = Catalog.to_text(catalog.policies)

    assert text =~ "turnstile_fixture_folders turnstile_gate_edit update\n"
    assert text =~ "  WITH CHECK -\n"
  end

  test "a migrations table that holds no version is an invalid catalog" do
    binding = binding!(migrations_table: Probe.empty_versions())

    assert %Error.Invalid{what: :catalog, detail: detail} = catch_error(Catalog.read!(binding))
    assert detail == "#{Probe.empty_versions()} holds no migration version"
  end

  defp names do
    ~w(
      turnstile_admit_delete
      turnstile_admit_insert
      turnstile_exempt_turnstile_owner_select
      turnstile_gate_edit
      turnstile_scope_edit
      turnstile_scope_read
    )
  end

  defp binding!(overrides \\ []) do
    {:ok, binding} = Binding.new(Keyword.merge([repo: Sandboxed, schemas: [Folder, Item]], overrides))
    binding
  end
end
