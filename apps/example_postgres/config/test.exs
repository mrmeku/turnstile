import Config

# The ephemeral cluster configures and starts the repos from the test
# helper, after the application has started, so the application starts
# none of its own.
config :example_postgres, start_repos: false
