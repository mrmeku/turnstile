alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Ledger.TestMigrations
alias Turnstile.Ledger.TestRepos

Turnstile.Test.Cluster.start(
  otp_app: :turnstile_ledger,
  repos: [
    {TestRepos.Owner, role: :owner, database: :sandboxed, pool_size: 2},
    {TestRepos.App, role: :app, database: :sandboxed, pool: Sandbox},
    {TestRepos.CommittedOwner, role: :owner, database: :committed, pool_size: 2},
    {TestRepos.CommittedApp, role: :app, database: :committed, pool_size: 5}
  ],
  migrate: fn repo ->
    migrations = [{1, TestMigrations.Counter}, {2, TestMigrations.Events}]
    _versions = Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)
    Turnstile.Fixture.Tables.create!(repo)
  end
)

Sandbox.mode(TestRepos.App, :manual)
ExUnit.start()
