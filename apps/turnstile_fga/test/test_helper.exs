alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Fga.TestMigrations
alias Turnstile.TestRepos.Sandboxed

# The checkpoint table in both tiers of the cluster, created by the migration
# helper through a thin application's kind of migration. No fixture table is
# needed: the cases here fold events the probe builds. No server is started.
Turnstile.Test.Cluster.start(
  otp_app: :turnstile_core,
  repos: [
    {Sandboxed, role: :app, database: :sandboxed, pool: Sandbox},
    {Turnstile.TestRepos.Committed, role: :app, database: :committed, pool_size: 2},
    {Turnstile.TestRepos.Owner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    Turnstile.Test.CounterTable.create!(repo)
    _versions = Ecto.Migrator.run(repo, [{1, TestMigrations.Checkpoint}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
