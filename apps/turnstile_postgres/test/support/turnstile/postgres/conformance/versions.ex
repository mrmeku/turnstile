defmodule Turnstile.Postgres.Conformance.Versions do
  @moduledoc """
  The change-management artifact of row-level security: tightening drops
  the folders' read policy through the owner repo, writes one that admits
  a reader's membership alone, records a migration after the boot one so
  the version the catalog reads moves, reloads the catalog, and publishes
  the version; restoring puts the boot policy back, takes the migration
  row out, and reloads. A policy is in force for the next statement, so
  neither waits. The rows go through the committed connection, which is
  why the template requires `committed:` beside `versions:`.
  """

  @behaviour Turnstile.Conformance.Versions

  alias Turnstile.Conformance.Versions
  alias Turnstile.Postgres.Conformance.Rules
  alias Turnstile.Postgres.Migration
  alias Turnstile.Postgres.Policy
  alias Turnstile.Postgres.Version
  alias Turnstile.TestRepos.Owner

  @version 20_260_915_000_002
  @folders "turnstile_fixture_folders"

  @impl Versions
  def event, do: Version.telemetry_event()

  @impl Versions
  def tighten do
    :ok = swap!(Rules.folder_read("reader"))
    _result = Owner.query!("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, now())", [@version])
    _catalog = Turnstile.Postgres.reload!()

    version =
      Migration.publish!(Owner,
        tables: Rules.tables(),
        version: @version,
        author: "turnstile_postgres",
        approval: "the conformance suite"
      )

    {:ok, version}
  end

  @impl Versions
  def restore do
    :ok = swap!(Rules.folder_read(nil))
    _result = Owner.query!("DELETE FROM schema_migrations WHERE version = $1", [@version])
    _catalog = Turnstile.Postgres.reload!()
    :ok
  end

  defp swap!(using) do
    _result = Owner.query!("DROP POLICY #{Policy.scope_name("read")} ON #{@folders}", [])
    Migration.policy!(Owner, table: @folders, operation: :read, using: using)
  end
end
