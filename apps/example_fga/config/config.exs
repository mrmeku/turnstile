import Config

# The server the adapter asks and the store it keeps this application's
# tuples in. The store is named by a deployment, because a store is created
# once and then holds the tuples every node of the deployment reads. How
# often the drain passes is the runner's, and how far it has got is the
# cursor's in the database.
config :example_fga,
  endpoint: System.get_env("FGA_ENDPOINT", "127.0.0.1:8080"),
  store_id: System.get_env("FGA_STORE_ID", "turnstile-example")

if config_env() == :test do
  import_config "test.exs"
end
