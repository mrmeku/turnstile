alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Ledger.TestRepos

Turnstile.Test.Cluster.start(
  otp_app: :turnstile_ledger,
  repos: [
    {TestRepos.Owner, role: :owner, database: :sandboxed, pool_size: 2},
    {TestRepos.App, role: :app, database: :sandboxed, pool: Sandbox},
    {TestRepos.CommittedOwner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    _versions = Ecto.Migrator.run(repo, [{1, Turnstile.Ledger.TestMigrations.Counter}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(TestRepos.App, :manual)
ExUnit.start()
