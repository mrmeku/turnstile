alias Ecto.Adapters.SQL.Sandbox
alias Turnstile.TestRepos.Sandboxed

# One sidecar for the run, reading the conformance policies where they sit
# in the repository, and the fixture's tables in both tiers of the cluster.
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

_shared = Turnstile.Test.Cerbos.start_shared(policies: "priv/conformance")

Sandbox.mode(Sandboxed, :manual)
ExUnit.start()
