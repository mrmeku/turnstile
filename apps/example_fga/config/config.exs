import Config

# The server the adapter asks, the store it keeps this application's tuples
# in, and how often the projector drains the ledger into that store. The
# store is named by a deployment, because a store is created once and then
# holds the tuples every node of the deployment reads.
config :example_fga,
  endpoint: System.get_env("FGA_ENDPOINT", "127.0.0.1:8080"),
  store_id: System.get_env("FGA_STORE_ID", "turnstile-example"),
  drain_interval: 1_000

# The ledger this application boots with. This adapter requires one: the
# store is a projection of the ledger rather than the application's tables,
# so there is nothing to drain without it, and boot fails rather than
# pretend a dual write is a projection.
config :example_fga, ledger: {Turnstile.Ledger.Ecto, repo: Example.Repo, owner_repo: Example.OwnerRepo}

if config_env() == :test do
  import_config "test.exs"
end
