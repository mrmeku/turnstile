alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.Postgres.Conformance.Rules
alias Turnstile.TestRepos.Sandboxed

# The fixture's tables are created by the owner role, then the conformance
# migration protects them and writes the policies. Both run once per
# database, so the sandboxed tier and the committed tier hold the same rules.
Turnstile.Test.Cluster.start(
  otp_app: :turnstile_core,
  repos: [
    {Sandboxed, role: :app, database: :sandboxed, pool: Sandbox},
    {Turnstile.TestRepos.Committed, role: :app, database: :committed, pool_size: 2},
    {Turnstile.TestRepos.Owner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    Turnstile.Test.CounterTable.create!(repo)
    Turnstile.Fixture.Tables.create!(repo)
    Turnstile.Postgres.Probe.create!(repo)
    [_rls] = Ecto.Migrator.run(repo, [{Rules.version(), Rules}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
