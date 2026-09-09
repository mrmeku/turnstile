import Config

# The store and the server of the run are the test helper's to name: the
# helper raises a server on a free port and creates a store on it, and each
# test creates a store of its own. What is here is what boot validates
# against the adapter's schema before either exists.
config :example_fga, endpoint: "127.0.0.1:8080", store_id: "turnstile-example"

# The ephemeral cluster configures and starts the repos from the test
# helper, after the application has started, so the application starts none
# of its own, and with them the projector: a test drains by hand, and a
# process draining beside it would read the ledger from a connection of its
# own.
config :example_fga, start_repos: false
