alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Relay.TestMigrations
alias Turnstile.Relay.TestTables
alias Turnstile.TestRepos.Committed
alias Turnstile.TestRepos.Owner
alias Turnstile.TestRepos.Sandboxed

# The cursor table in both tiers of the cluster, raised by the migration
# helper through the kind of migration an application writes, and the two
# tables the test job works over beside it. Most of the suite runs on the
# sandboxed tier, one test per transaction; the committed tier is where two
# connections contend for one runner's lock and where the migration is taken
# down and raised again.
Turnstile.Dev.Cluster.start(
  otp_app: :turnstile,
  repos: [
    {Sandboxed, role: :app, database: :sandboxed, pool: Sandbox},
    {Committed, role: :app, database: :committed, pool_size: 4},
    {Owner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    TestTables.create!(repo)
    _versions = Ecto.Migrator.run(repo, [{1, TestMigrations.Cursor}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
