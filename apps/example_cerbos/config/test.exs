import Config

# The commit the suite runs under, pinned rather than read from the
# environment, so every decision the suite records names one known commit.
config :example_cerbos, commit: "policies-0001"

# The ephemeral cluster configures and starts the repos from the test
# helper, after the application has started, so the application starts
# none of its own.
config :example_cerbos, start_repos: false
