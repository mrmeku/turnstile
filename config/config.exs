import Config

# Each app's own config is imported here so one umbrella build serves every app.
# The test repos are configured at boot by Turnstile.Test.Cluster, not here.
for config <- "../apps/*/config/config.exs" |> Path.expand(__DIR__) |> Path.wildcard() do
  import_config config
end

if config_env() == :test do
  config :logger, level: :warning
end
