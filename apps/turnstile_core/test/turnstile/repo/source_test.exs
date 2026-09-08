defmodule Turnstile.Repo.SourceTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Ecto.Changeset
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Repo.Source

  test "root/1 answers the schema, table name, or nil for every shape the Repo takes" do
    assert Source.root(Folder) == Folder
    assert Source.root("turnstile_fixture_folders") == "turnstile_fixture_folders"
    assert Source.root({"turnstile_fixture_folders", Folder}) == Folder
    folders = from(f in Folder, select: f.id)
    items = from(t in "turnstile_fixture_items", select: t.id)
    over_folders = from(s in subquery(folders), select: s.id)
    over_items = from(s in subquery(items), select: s.id)
    assert Source.root(folders) == Folder
    assert Source.root(over_folders) == Folder
    assert Source.root(items) == "turnstile_fixture_items"
    assert Source.root(over_items) == "turnstile_fixture_items"
    assert Source.root(%Item{}) == Item
    assert Source.root(Changeset.change(%Item{})) == Item
    assert Source.root([%Item{}, %Folder{}]) == Item
    assert Source.root([]) == nil
    assert Source.root(nil) == nil
  end

  test "to_query/1 turns a schema, struct, changeset, or list into the query the adapter sees" do
    assert %Ecto.Query{from: %{source: {"turnstile_fixture_folders", Folder}}} = Source.to_query(Folder)
    assert %Ecto.Query{from: %{source: {"turnstile_fixture_items", Item}}} = Source.to_query(%Item{})
    assert %Ecto.Query{from: %{source: {"turnstile_fixture_items", Item}}} = Source.to_query(Changeset.change(%Item{}))
    assert %Ecto.Query{from: %{source: {"turnstile_fixture_items", Item}}} = Source.to_query([%Item{}])
    assert %Ecto.Query{} = query = from(f in Folder, select: f.id)
    assert Source.to_query(query) == query
    assert %Ecto.Query{from: %{source: {"t", Folder}}} = Source.to_query({"t", Folder})
    assert Source.to_query([]) == nil
    assert Source.to_query(nil) == nil
  end
end
