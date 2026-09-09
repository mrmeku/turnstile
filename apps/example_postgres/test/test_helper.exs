alias Ecto.Adapters.SQL.Sandbox

# The migrations, loaded once: the cluster migrates each of its databases,
# and loading the files per database would redefine their modules. A replay
# raises a database of its own and migrates it too, so the list is put where
# a test can read it rather than loaded again there.
migrations =
  for file <- Enum.sort(Path.wildcard("priv/repo/migrations/*.exs")) do
    [{module, _binary}] = Code.require_file(file)
    {version, _name} = Integer.parse(Path.basename(file))
    {version, module}
  end

:ok = Application.put_env(:example_postgres, :migrations, migrations)

# Both repos point at one database: the committed scenarios run on the app
# repo outside a sandbox and truncate through the owner repo when they end.
# The repos are configured under the example's otp_app, where their
# modules read their configuration from.
Turnstile.Test.Cluster.start(
  otp_app: :turnstile_example,
  repos: [
    {Example.Repo, role: :app, database: :sandboxed, pool: Sandbox},
    {Example.OwnerRepo, role: :owner, database: :sandboxed, pool_size: 2}
  ],
  migrate: fn repo ->
    [_domain, _counter, _events, _genesis, _rules] = Ecto.Migrator.run(repo, migrations, :up, all: true, log: false)
    :ok
  end
)

# The policies and the version they are at, read once the repos are up, and
# the version published: a migration runs with no repo to write a ledger
# event through, so the publish waits for the tree the cluster started.
_catalog = Turnstile.Postgres.load!()
{:ok, _published} = ExamplePostgres.publish()

Sandbox.mode(Example.Repo, :manual)

exclude =
  case Application.fetch_env!(:example_postgres, :ledger) do
    :none -> [needs_ledger: true]
    _ledger -> []
  end

ExUnit.start(exclude: exclude)
