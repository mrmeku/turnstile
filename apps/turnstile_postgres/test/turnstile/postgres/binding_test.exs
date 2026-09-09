defmodule Turnstile.Postgres.BindingTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Postgres.Binding
  alias Turnstile.TestRepos.Sandboxed

  defmodule Undeclared do
    @moduledoc false
    use Ecto.Schema

    schema "turnstile_binding_test_rows" do
      field(:name, :string)
    end
  end

  test "the binding names the repo, the schemas, and the table the version is read from" do
    assert {:ok, binding} = Binding.new(repo: Sandboxed, schemas: [Folder])
    assert {binding.repo, binding.schemas, binding.migrations_table} == {Sandboxed, [Folder], "schema_migrations"}
  end

  test "a schema that did not use Turnstile.Schema is refused by name" do
    assert {:error, %Error.Invalid{what: :binding, detail: detail}} =
             Binding.new(repo: Sandboxed, schemas: [Folder, Undeclared])

    assert detail =~ "Undeclared"
  end

  test "a missing repo is refused" do
    assert {:error, %Error.Invalid{what: :binding}} = Binding.new(schemas: [Folder])
  end

  test "an override is read from the calling process and from its callers" do
    :ok = Binding.override(repo: Sandboxed, schemas: [Folder, Item])
    assert {:ok, binding} = Binding.resolve()
    assert Binding.tables(binding) == ["turnstile_fixture_folders", "turnstile_fixture_items"]

    task = Task.async(fn -> Binding.resolve() end)
    assert {:ok, ^binding} = Task.await(task)
  end

  test "an override around a function is put back afterwards" do
    :ok = Binding.override(repo: Sandboxed, schemas: [Folder])

    inner = Binding.override([schemas: [Item]], fn -> Binding.resolve() end)
    assert {:ok, %Binding{schemas: [Item]}} = inner
    assert {:ok, %Binding{schemas: [Folder]}} = Binding.resolve()
  end

  test "with nothing bound and no override, resolve says so" do
    assert {:error, %Error.Invalid{what: :binding, detail: "nothing bound and no override"}} = Binding.resolve()
  end

  test "an object type resolves to its schema, table, and primary key, and an unknown one to nothing" do
    assert {:ok, binding} = Binding.new(repo: Sandboxed, schemas: [Folder, Item, Membership, Account])
    assert Binding.target(binding, :folder) == {Folder, "turnstile_fixture_folders", :id}
    assert Binding.target(binding, :item) == {Item, "turnstile_fixture_items", :id}
    assert Binding.target(binding, :document) == nil
  end

  test "the binding round-trips through the keyword list its schema validates" do
    assert %NimbleOptions{} = Binding.options_schema()
    assert {:ok, binding} = Binding.new(repo: Sandboxed, schemas: [Folder])

    assert Binding.to_keyword(binding) == [repo: Sandboxed, schemas: [Folder], migrations_table: "schema_migrations"]
    assert Binding.new(Binding.to_keyword(binding)) == {:ok, binding}
  end

  test "a table resolves back to the schema whose declarations cover it" do
    assert {:ok, binding} = Binding.new(repo: Sandboxed, schemas: [Folder, Membership])
    assert Binding.schema_of(binding, "turnstile_fixture_memberships") == Membership
    assert Binding.schema_of(binding, "pg_class") == nil
  end
end
