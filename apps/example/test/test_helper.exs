alias Ecto.Adapters.SQL.Sandbox
alias Example.Infrastructure.Repo

Turnstile.Dev.Cluster.start(
  otp_app: :example,
  repos: [
    {Repo, role: :app, database: :sandboxed, pool: Sandbox},
    {Example.Infrastructure.OwnerRepo, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    [1] = Ecto.Migrator.run(repo, [{1, Example.Fixture.Migration}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(Repo, :manual)
ExUnit.start()
