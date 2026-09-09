import Config

# The ledger mode this application boots with. The test configuration reads
# it from EXAMPLE_LEDGER so the suite runs once per mode.
config :example_postgres, ledger: :none

if config_env() == :test do
  import_config "test.exs"
end
