import Config

# The ledger mode this application boots with. The test configuration reads
# it from EXAMPLE_LEDGER so the suite runs once per mode.
config :example_rbac, ledger: :none

if config_env() in [:dev, :test] do
  import_config "#{config_env()}.exs"
end
