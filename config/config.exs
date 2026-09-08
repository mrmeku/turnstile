import Config

# Each app's own config is imported here so one umbrella build serves every app.
# The test repos are configured at boot by Turnstile.Test.Cluster, not here.
for config <- Path.wildcard(Path.expand("../apps/*/config/config.exs", __DIR__)) do
  import_config config
end

if config_env() == :test do
  config :logger, level: :warning
end
