alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Dev.TestRepos.Sandboxed

Turnstile.Dev.Cluster.start(
  otp_app: :turnstile_dev,
  repos: [
    {Sandboxed, role: :app, database: :sandboxed, pool: Sandbox},
    {Turnstile.Dev.TestRepos.Committed, role: :app, database: :committed, pool_size: 2},
    {Turnstile.Dev.TestRepos.Owner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    _versions = Ecto.Migrator.run(repo, [{1, Turnstile.Dev.TestMigration}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
