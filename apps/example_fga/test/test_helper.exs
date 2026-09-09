alias Ecto.Adapters.SQL.Sandbox

# The migrations, loaded once: the cluster migrates each of its databases,
# and loading the files per database would redefine their modules.
migrations =
  for file <- Enum.sort(Path.wildcard("priv/repo/migrations/*.exs")) do
    [{module, _binary}] = Code.require_file(file)
    {version, _name} = Integer.parse(Path.basename(file))
    {version, module}
  end

:ok = Application.put_env(:example_fga, :migrations, migrations)

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

# One server for the run, on a free port with the in-memory datastore, and a
# store on it for the boot the application would do: the store every test
# reads is one of its own, which `ExampleFga.Rules` creates per test, and this
# one carries the model the ledger's boot version names.
server = Turnstile.Test.Fga.start_shared([])
{:ok, store} = Turnstile.Fga.Client.Http.create_store(server.address, "example-fga-boot")

_config =
  Turnstile.Config.boot!(
    adapter: {Turnstile.Fga, endpoint: server.address, store_id: store},
    ledger: Application.fetch_env!(:example_fga, :ledger)
  )

_binding =
  Turnstile.Fga.Binding.bind!(
    repo: Example.Repo,
    model: ExampleFga.model(),
    mapping: ExampleFga.TupleMapping,
    guard: ExampleFga.Guard,
    author: ExampleFga.author(),
    approval: ExampleFga.approval()
  )

# The model published once the repos are up, which a ledger mode writes as an
# event: the application starts no repo to write it through when the cluster
# owns them. The id it comes back with is pinned for the boot, so a process
# that asks without a store of its own asks under the model of this store.
{:ok, %Turnstile.FactEvent{new: %Turnstile.PolicyVersion{version: model}}} = Turnstile.Fga.publish()

_pinned =
  Turnstile.Config.boot!(
    adapter: {Turnstile.Fga, endpoint: server.address, store_id: store, model_id: model},
    ledger: Application.fetch_env!(:example_fga, :ledger)
  )

Sandbox.mode(Example.Repo, :manual)

ExUnit.start()
