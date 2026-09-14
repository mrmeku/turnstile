alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Fga.TestMigrations
alias Turnstile.TestRepos.Sandboxed

# The outbox table and the relay's cursor table in both tiers of the cluster,
# created by the migration helpers through a thin application's kind of
# migration, and the neutral fixture's tables beside them, which the
# conformance template writes worlds into. One server for the run, with the
# in-memory datastore, and a store per test inside it.
Turnstile.Test.Cluster.start(
  otp_app: :turnstile,
  repos: [
    {Sandboxed, role: :app, database: :sandboxed, pool: Sandbox},
    {Turnstile.TestRepos.Committed, role: :app, database: :committed, pool_size: 2},
    {Turnstile.TestRepos.Owner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    Turnstile.Fixture.Tables.create!(repo)
    _versions = Ecto.Migrator.run(repo, [{1, TestMigrations.Outbox}], :up, all: true, log: false)
    :ok
  end
)

_shared = Turnstile.Dev.Fga.start_shared()

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
