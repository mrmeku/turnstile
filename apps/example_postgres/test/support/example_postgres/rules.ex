defmodule ExamplePostgres.Rules do
  @moduledoc """
  The policy operations the scenarios need from this binding. The rules are
  the database's own, so a rule change is a schema change: the read policy
  of a document is dropped and written again under a tightened expression,
  a migration row records the version the database is now at, the loaded
  catalog is read again so calls see it, and the version reaches the ledger.
  The statements run through the owner-role repo, which is what owns the
  protected tables.

  A replay is the same fact from the other side: the rules of the version
  are the database's, so getting them back takes a database of its own,
  carrying the rows the tables hold, the relationships the fold names, and
  the policies of that version where the migrations put theirs. The catalog
  the calls read is loaded from that database for the length of the question
  and from the live one after it.
  """

  @behaviour Example.Scenarios.Rules

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios,
      ExamplePostgres,
      Ecto,
      Turnstile,
      Turnstile.Ledger.Replay,
      Turnstile.Postgres,
      Turnstile.Test
    ]

  alias Example.Fixture
  alias Example.OwnerRepo
  alias Example.Repo
  alias Example.Scenarios.Rules
  alias ExamplePostgres.Policies
  alias Turnstile.Error
  alias Turnstile.Ledger.Replay
  alias Turnstile.Postgres.Migration
  alias Turnstile.Test.Cluster

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

  @impl Rules
  def replay(%Replay{} = replay, fun) when is_function(fun, 0) do
    policies = policies!(replay)

    try do
      Cluster.scratch!(Cluster.info(), [{OwnerRepo, :owner}, {Repo, :app}], fn instances ->
        :ok = migrate!()
        :ok = build!(instances[OwnerRepo], policies, replay)
        _scratch = Turnstile.Postgres.reload!()
        fun.()
      end)
    after
      _live = Turnstile.Postgres.reload!()
    end
  end

  # The tables and the ledger of the scratch database, raised by the same
  # migrations the live one was, so the version's policies land where the
  # migrations' own were and the copy has somewhere to go.
  defp migrate! do
    migrations = Application.fetch_env!(:example_postgres, :migrations)
    _run = Ecto.Migrator.run(OwnerRepo, migrations, :up, all: true, log: false)
    :ok
  end

  defp build!(scratch, policies, %Replay{} = replay) do
    Turnstile.Postgres.Replay.build!(OwnerRepo,
      tables: Fixture.tables(),
      from: OwnerRepo,
      to: scratch,
      policies: policies,
      state: fn -> Fixture.restore!(replay.fold) end
    )
  end

  # The policies of the version by value. A version above the content cap
  # carries a pointer to the tables instead, and reading those back is the
  # migration of that number applied to a database of its own.
  defp policies!(%Replay{policy_version: version}) do
    case version do
      %{content: text} when is_binary(text) ->
        text

      %{version: number, pointer: pointer} ->
        raise %Error.Unsupported{
          adapter: Turnstile.Postgres,
          feature: :replay,
          note:
            "version #{number} carries #{pointer} rather than its policies: apply that migration to a scratch database"
        }
    end
  end

  defp drop_read, do: run("DROP POLICY #{@read} ON #{@documents}", [])

  defp read(using) do
    Migration.policy!(OwnerRepo, table: @documents, operation: :read, using: using)
  end

  # The version a decision names is the highest migration the database
  # holds, so a rule change writes its own row and its undo removes it.
  defp record(version) do
    run("INSERT INTO schema_migrations (version, inserted_at) VALUES ($1, now())", [version])
  end

  defp forget(version), do: run("DELETE FROM schema_migrations WHERE version = $1", [version])

  defp run(statement, params) do
    _result = OwnerRepo.query!(statement, params)
    :ok
  end
end
