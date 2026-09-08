defmodule Turnstile.Fixture.Tables do
  @moduledoc "Creates the fixture tables and the application role's grants, through an owner-role repo."

  use Boundary, top_level?: true, deps: []

  @names ~w(turnstile_fixture_folders turnstile_fixture_items turnstile_fixture_memberships)

  @tables [
    "CREATE TABLE turnstile_fixture_folders (id bigserial PRIMARY KEY, name text)",
    "CREATE TABLE turnstile_fixture_items (id bigserial PRIMARY KEY, title text, " <>
      "folder_id bigint REFERENCES turnstile_fixture_folders(id))",
    "CREATE TABLE turnstile_fixture_memberships (id bigserial PRIMARY KEY, account_id text, role text, " <>
      "folder_id bigint REFERENCES turnstile_fixture_folders(id))",
    "CREATE TABLE turnstile_fixture_accounts (id text PRIMARY KEY, clearance text)"
  ]

  @doc "Creates the tables. The repo is an owner-role repo whose calls carry the library exemption."
  @spec create!(module()) :: :ok
  def create!(repo) when is_atom(repo) do
    Enum.each(@tables, &repo.query!/1)

    Enum.each(@names, fn name ->
      repo.query!("GRANT SELECT, INSERT, UPDATE, DELETE ON #{name} TO turnstile_app")
      repo.query!("GRANT USAGE, SELECT ON SEQUENCE #{name}_id_seq TO turnstile_app")
    end)

    repo.query!("GRANT SELECT, INSERT, UPDATE, DELETE ON turnstile_fixture_accounts TO turnstile_app")
    :ok
  end
end
