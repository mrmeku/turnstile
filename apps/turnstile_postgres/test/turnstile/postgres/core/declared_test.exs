defmodule Turnstile.Postgres.Core.DeclaredTest do
  use ExUnit.Case, async: true

  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Carried.Folder
  alias Turnstile.Postgres.Carried.Item
  alias Turnstile.Postgres.Carried.Shelf
  alias Turnstile.Postgres.Core.Declared
  alias Turnstile.TestRepos.Sandboxed

  test "a carried relation declares the key of the schema that holds it, and one carried through another declares none" do
    {:ok, binding} = Binding.new(repo: Sandboxed, schemas: [Shelf, Folder, Item])

    columns = [
      {"turnstile_carried_folders", "shelf_id"},
      {"turnstile_carried_items", "folder_id"}
    ]

    assert Declared.findings(binding, columns) == [{Item, "folder_id"}]
    assert Declared.describe([{Item, "folder_id"}]) == "folder_id of #{inspect(Item)}"
  end
end
