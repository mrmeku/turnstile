alias Ecto.Adapters.SQL.Sandbox

Turnstile.Dev.Cluster.start(
  otp_app: :example,
  repos: [
    {Example.Repo, role: :app, database: :sandboxed, pool: Sandbox},
    {Example.OwnerRepo, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn repo ->
    [1] = Ecto.Migrator.run(repo, [{1, Example.Fixture.Migration}], :up, all: true, log: false)
    :ok
  end
)

Sandbox.mode(Example.Repo, :manual)
ExUnit.start()
