defmodule ExamplePostgres.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding. The rules are
  the database's own, so a rule change is a schema change: the read policy
  of a document is dropped and written again under a tightened expression,
  a migration row records the version the database is now at, the loaded
  catalog is read again so calls see it, and the version reaches the ledger.
  The statements run through the owner-role repo, which is what owns the
  protected tables.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary, top_level?: true, deps: [Example, Example.Scenarios, ExamplePostgres, Turnstile, Turnstile.Postgres]

  alias Example.Scenarios.Rules
  alias ExamplePostgres.Policies
  alias Turnstile.Postgres.Migration

  @tightened ~w(lead)
  @version 20_260_909_000_006
  @read "turnstile_scope_read"
  @documents "documents"

  @impl Rules
  def publish_tightened do
    drop_read()
    :ok = read(Policies.document_read(@tightened))
    :ok = record(@version)
    _catalog = Turnstile.Postgres.reload!()
    ExamplePostgres.publish()
  end

  @impl Rules
  def restore do
    drop_read()
    :ok = read(Policies.document_read(Policies.readers()))
    :ok = forget(@version)
    _catalog = Turnstile.Postgres.reload!()
    :ok
  end

  @impl Rules
  def publish_boot do
    {:ok, _published} = ExamplePostgres.publish()
    :ok
  end

  defp drop_read, do: run("DROP POLICY #{@read} ON #{@documents}", [])

  defp read(using) do
    Migration.policy!(Example.OwnerRepo, table: @documents, operation: :read, using: using)
  end

  # The version a decision names is the highest migration the database
  # holds, so a rule change writes its own row and its undo removes it.
  defp record(version) do
    run("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, now())", [version])
  end

  defp forget(version), do: run("DELETE FROM schema_migrations WHERE version = $1", [version])

  defp run(statement, params) do
    _result = Example.OwnerRepo.query!(statement, params)
    :ok
  end
end
