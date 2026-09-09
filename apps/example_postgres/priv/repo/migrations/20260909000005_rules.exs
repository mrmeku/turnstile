defmodule ExamplePostgres.Repo.Migrations.Rules do
  @moduledoc false
  use Ecto.Migration

  alias ExamplePostgres.Policies
  alias Turnstile.Config
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Migration

  @version 20_260_909_000_005
  @app Policies.app_role()
  @owner Policies.owner_role()
  @documents "documents"
  @markings "markings"
  @portions "portions"
  @proposals "marking_proposals"

  def up do
    repo = repo()
    Enum.each(Policies.protected(), &execute("ALTER TABLE #{&1} OWNER TO #{@owner}"))
    Enum.each(Policies.accessors(), &execute/1)
    flush()
    Enum.each(Policies.protected(), &Migration.protect!(repo, &1))
    documents(repo)
    markings(repo)
    portions(repo)
    proposals(repo)
    :ok = Migration.grant!(repo, table: "schema_migrations", to: @app, commands: [:select])
    _version = Migration.publish!(repo, published())
    :ok
  end

  def down do
    repo = repo()
    Enum.each(Catalog.policies!(repo, Policies.protected()), &execute("DROP POLICY #{&1.name} ON #{&1.table}"))
    Enum.each(Policies.protected(), &execute("ALTER TABLE #{&1} NO FORCE ROW LEVEL SECURITY"))
    Enum.each(Policies.protected(), &execute("ALTER TABLE #{&1} DISABLE ROW LEVEL SECURITY"))
    Enum.each(Policies.accessor_drops(), &execute/1)
    execute("REVOKE SELECT ON schema_migrations FROM #{@app}")
    :ok
  end

  # A document answers `read` under every rule and `read_redacted` under
  # lawful purpose alone; the marking operations reach it through the
  # designating office, and the three that write it carry the gate as well.
  defp documents(repo) do
    scope(repo, @documents, :read, Policies.document_read(Policies.readers()))
    scope(repo, @documents, :read_redacted, Policies.document_read_redacted())
    Enum.each([:change_marking, :set_decontrol, :decontrol], &scope(repo, @documents, &1, Policies.document_marks()))
    scope(repo, @documents, :propose_marking, Policies.document_designator())
    scope(repo, @documents, :approve_marking, Policies.document_approver())
    Enum.each([:change_marking, :set_decontrol, :decontrol], &gate(repo, @documents, &1, Policies.document_marks()))
    exempt(repo, @documents, [:select, :insert])
  end

  # The banner is reached through its document, whose policy is what admits
  # the read, so every read of a marking is admitted here and the two write
  # gates are what the table enforces: the designator's change, and the
  # approval of somebody else's proposal.
  defp markings(repo) do
    :ok = Migration.admit!(repo, table: @markings, command: :select)
    gate(repo, @markings, :change_marking, Policies.marking_marks())
    gate(repo, @markings, :approve_marking, Policies.marking_approves())
    :ok = Migration.exempt!(repo, table: @markings, to: @app, commands: [:insert, :update])
  end

  defp portions(repo) do
    scope(repo, @portions, :read, Policies.portion_read())
    scope(repo, @portions, :change_marking, Policies.portion_marks())
    gate(repo, @portions, :change_marking, Policies.portion_marks())
    exempt(repo, @portions, [:select, :insert])
  end

  defp proposals(repo) do
    scope(repo, @proposals, :propose_marking, Policies.proposal_proposer())
    scope(repo, @proposals, :approve_marking, Policies.proposal_approver())
    gate(repo, @proposals, :approve_marking, Policies.proposal_approver())

    :ok =
      Migration.gate!(repo,
        table: @proposals,
        operation: :propose_marking,
        command: :insert,
        with_check: Policies.proposal_written()
      )

    exempt(repo, @proposals, [:select])
  end

  defp scope(repo, table, operation, using) do
    :ok = Migration.policy!(repo, table: table, operation: operation, using: using)
  end

  # The gate reads `true` before the write, so the row is there for the
  # database to apply `WITH CHECK` to and a write that violates the rule is
  # refused rather than silently matching nothing.
  defp gate(repo, table, operation, with_check) do
    :ok = Migration.gate!(repo, table: table, operation: operation, using: "true", with_check: with_check)
  end

  # The application's own statements outside a decision, which is what the
  # seam leaves behind when it admits a call under a declared exemption,
  # and the owner's reads, which the accessor functions and the reconcile
  # run under.
  defp exempt(repo, table, commands) do
    :ok = Migration.exempt!(repo, table: table, to: @app, commands: commands)
    :ok = Migration.exempt!(repo, table: table, to: @owner, commands: [:select], outside_decision: false)
  end

  defp published do
    [tables: Policies.protected(), ledger: ledger()] ++ ExamplePostgres.published(to_string(@version))
  end

  # A migration runs with nothing booted, as the schema dump runs it, and
  # before the repo an event is written through is started, as the test
  # cluster runs it. Either way there is no ledger to append to here and
  # the version is recorded by telemetry alone; the boot that follows
  # publishes it into the ledger it then has.
  defp ledger do
    with {:ok, %Config{ledger: {module, options}}} <- Config.resolve(),
         true <- is_pid(Process.whereis(options[:repo])) do
      {module, options}
    else
      _unavailable -> :none
    end
  end
end
