import Config

# EXAMPLE_LEDGER selects the ledger mode of the test run: `ecto` records
# every fact write in `turnstile_ledger_events`, `none` boots without a
# ledger and the suite skips what a ledger is needed for.
ledger =
  case System.get_env("EXAMPLE_LEDGER", "ecto") do
    "ecto" -> {Turnstile.Ledger.Ecto, repo: Example.Repo, owner_repo: Example.OwnerRepo}
    "none" -> :none
    other -> raise ArgumentError, "EXAMPLE_LEDGER=#{other}: the modes are ecto and none"
  end

config :example_rbac, ledger: ledger

# The ephemeral cluster configures and starts the repos from the test
# helper, after the application has started, so the application starts
# none of its own.
config :example_rbac, start_repos: false
