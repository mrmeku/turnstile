import Config

# EXAMPLE_LEDGER selects the ledger mode of the test run: `none` boots
# without a ledger. The ledger stage adds `ecto`.
ledger =
  case System.get_env("EXAMPLE_LEDGER", "none") do
    "none" -> :none
    other -> raise ArgumentError, "EXAMPLE_LEDGER=#{other}: only none is available until the ledger stage"
  end

config :example_rbac, ledger: ledger

# The ephemeral cluster configures and starts the repos from the test
# helper, after the application has started, so the application starts
# none of its own.
config :example_rbac, start_repos: false
