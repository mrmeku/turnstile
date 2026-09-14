alias Ecto.Adapters.SQL.Sandbox

# The migrations, loaded once: the cluster migrates each of its databases,
# and loading the files per database would redefine their modules.
migrations =
  for file <- Enum.sort(Path.wildcard("priv/repo/migrations/*.exs")) do
    [{module, _binary}] = Code.require_file(file)
    {version, _name} = Integer.parse(Path.basename(file))
    {version, module}
  end

# Both repos point at one database: the committed scenarios run on the app
# repo outside a sandbox and truncate through the owner repo when they end.
# The repos are configured under the example's otp_app, where their
# modules read their configuration from.
Turnstile.Test.Cluster.start(
  otp_app: :example,
  repos: [
    {Example.Repo, role: :app, database: :sandboxed, pool: Sandbox},
    {Example.OwnerRepo, role: :owner, database: :sandboxed, pool_size: 2}
  ],
  migrate: fn repo ->
    [_domain] = Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)
    :ok
  end
)

# The version the policy is at, emitted once the repos are up: the
# application publishes nothing when the cluster owns them, so a run has one
# policy-version event rather than two.
{:ok, _published} = Turnstile.Code.publish()

Sandbox.mode(Example.Repo, :manual)

ExUnit.start()
