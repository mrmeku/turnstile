alias Ecto.Adapters.SQL.Sandbox

# The migrations, loaded once: the cluster migrates each of its databases,
# and loading the files per database would redefine their modules.
migrations =
  for file <- Enum.sort(Path.wildcard("priv/repo/migrations/*.exs")) do
    [{module, _binary}] = Code.require_file(file)
    {version, _name} = Integer.parse(Path.basename(file))
    {version, module}
  end

:ok = Application.put_env(:example_cerbos, :migrations, migrations)

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

# The policy files the run's sidecar serves are a copy under `tmp/`, not the
# committed ones: a scenario that publishes a rule change writes a file into
# the directory the sidecar watches, and it must be able to do that without
# changing the working tree. The copy also makes every publish a change to a
# file that is already there, which is what a directory watch reports.
run = Path.join([File.cwd!(), "tmp", "cerbos-" <> Base.url_encode64(:crypto.strong_rand_bytes(8), padding: false)])
policies = Path.join(run, "policies")
File.mkdir_p!(policies)
Enum.each(Path.wildcard("priv/policies/*.yaml"), &File.cp!(&1, Path.join(policies, Path.basename(&1))))

sidecar = Turnstile.Test.Cerbos.start_shared(policies: policies, dir: run)

# The address and the directory of the run's sidecar, and the file it writes
# its decision log to, put where every test reads them: the application
# booted against the configured address, which is a deployment's, and the
# sidecar the run raised takes a free port of its own.
_config =
  Turnstile.Config.boot!(
    adapter: {Turnstile.Cerbos, address: sidecar.address},
    ledger: Application.fetch_env!(:example_cerbos, :ledger)
  )

_binding =
  Turnstile.Cerbos.Binding.bind!(
    repo: Example.Repo,
    attributes: ExampleCerbos.Attributes,
    policies: sidecar.policies,
    commit: Application.fetch_env!(:example_cerbos, :commit),
    author: ExampleCerbos.author(),
    approval: ExampleCerbos.approval(),
    decision_log: sidecar.audit_log
  )

# The commit the sidecar is serving, published once the repos are up: in a
# ledger mode it is an event, and the application starts no repo to write it
# through when the cluster owns them.
{:ok, _published} = Turnstile.Cerbos.publish()

Sandbox.mode(Example.Repo, :manual)

exclude =
  case Application.fetch_env!(:example_cerbos, :ledger) do
    :none -> [needs_ledger: true]
    _ledger -> []
  end

ExUnit.start(exclude: exclude)
