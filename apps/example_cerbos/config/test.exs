import Config

# The commit the suite runs under, pinned rather than read from the
# environment: a scenario reads the commit a decision was made under, and
# compares it with the commit a tightened policy is published as.
config :example_cerbos, commit: "policies-0001"

# The ephemeral cluster configures and starts the repos from the test
# helper, after the application has started, so the application starts
# none of its own.
config :example_cerbos, start_repos: false
