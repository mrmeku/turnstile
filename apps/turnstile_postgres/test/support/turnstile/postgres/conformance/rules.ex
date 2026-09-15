defmodule Turnstile.Postgres.Conformance.Rules do
  @moduledoc """
  The fixture's rule as policies. A folder is readable by an account with
  a live membership on it held by the asking kind and editable when that
  membership is an editor's; an item answers as its folder does; and an
  account whose clearance is not the cleared one is refused either way. The
  kind and the moment are the session settings the adapter binds before
  each statement, and a setting the seam has cleared reads as the empty
  string, which is why the moment goes through `NULLIF` before its cast.

  Folders carry the update gate as well and items carry none, so a run
  covers both the gated path and the ungated one. Inserts and deletes on
  the two protected tables are admitted, because forcing row-level security
  refuses every statement no policy admits and the fixture writes its
  population through the same role it reads with.

  The owner role reads the protected tables while no operation is in force,
  which is the exemption the seam leaves behind for it. Forcing row-level
  security applies the policies to the table's owner too, so without that
  policy the role that owns the tables could not read their rows at all.

  The migration number is the policy version every decision over the
  fixture names, and the application role is granted `SELECT` on the
  migrations table so it can read that number back.
  """

  use Ecto.Migration

  alias Turnstile.Postgres.Migration

  @version 20_260_915_000_001
  @role "turnstile_app"
  @owner "turnstile_owner"
  @folders "turnstile_fixture_folders"
  @items "turnstile_fixture_items"

  @cleared """
  EXISTS (SELECT 1 FROM turnstile_fixture_accounts a
          WHERE a.id = current_setting('turnstile.subject_id', true) AND a.clearance = 'cleared')
  """

  @holding """
  m.account_id = current_setting('turnstile.subject_id', true)
            AND m.subject_kind = current_setting('turnstile.subject_kind', true)
            AND (m.expires_at IS NULL
                 OR m.expires_at > NULLIF(current_setting('turnstile.now', true), '')::timestamptz)
  """

  @folder_member """
  EXISTS (SELECT 1 FROM turnstile_fixture_memberships m
          WHERE m.folder_id = turnstile_fixture_folders.id
            AND #{@holding})
  """

  @folder_editor """
  EXISTS (SELECT 1 FROM turnstile_fixture_memberships m
          WHERE m.folder_id = turnstile_fixture_folders.id
            AND #{@holding}
            AND m.role = 'editor')
  """

  @item_member """
  EXISTS (SELECT 1 FROM turnstile_fixture_memberships m
          WHERE m.folder_id = turnstile_fixture_items.folder_id
            AND #{@holding})
  """

  @item_editor """
  EXISTS (SELECT 1 FROM turnstile_fixture_memberships m
          WHERE m.folder_id = turnstile_fixture_items.folder_id
            AND #{@holding}
            AND m.role = 'editor')
  """

  @doc "The migration number, which is the policy version a decision over the fixture names."
  @spec version() :: pos_integer()
  def version, do: @version

  @doc "The tables the policies protect."
  @spec tables() :: [String.t()]
  def tables, do: [@folders, @items]

  @doc "Protect the fixture's object tables, write the policies of its two operations, and publish the version."
  @spec up() :: :ok
  def up do
    repo = repo()
    rules(repo, @folders, @folder_member, @folder_editor)
    rules(repo, @items, @item_member, @item_editor)

    :ok =
      Migration.gate!(repo, table: @folders, operation: :edit, using: @folder_editor, with_check: @folder_editor)

    :ok = Migration.grant!(repo, table: "schema_migrations", to: @role, commands: [:select])
    _version = Migration.publish!(repo, published())
    :ok
  end

  defp rules(repo, table, member, editor) do
    :ok = Migration.protect!(repo, table)
    :ok = Migration.policy!(repo, table: table, operation: :read, using: "#{member} AND #{@cleared}")
    :ok = Migration.policy!(repo, table: table, operation: :edit, using: "#{editor} AND #{@cleared}")
    :ok = Migration.admit!(repo, table: table, command: :insert)
    :ok = Migration.admit!(repo, table: table, command: :delete)
    Migration.exempt!(repo, table: table, to: @owner, commands: [:select])
  end

  defp published do
    [
      tables: tables(),
      version: @version,
      author: "turnstile_postgres",
      approval: "the conformance suite"
    ]
  end
end
