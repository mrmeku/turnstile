alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.TestRepos.Sandboxed

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
  end
)

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
