import Config

# The development database `nix run .#services` raises: one database, the
# two roles, and the repos pointed at it by the roles they connect as. The
# test environment leaves the repos to the ephemeral cluster and configures
# none of this.
for {repo, role} <- [{Example.Repo, "turnstile_app"}, {Example.OwnerRepo, "turnstile_owner"}] do
  config :turnstile_example, repo,
    hostname: "127.0.0.1",
    port: 5432,
    username: role,
    database: "turnstile_dev",
    pool_size: 2
end

# A review of a past date is the fold of a ledger, so the development boot
# names one: without it `mix turnstile.review --at` has nothing to fold and
# says so rather than answering for today.
config :example_rbac, ledger: {Turnstile.Ledger.Ecto, repo: Example.Repo, owner_repo: Example.OwnerRepo}

# The review task prints a table, and a query log line per row of it would
# bury the table. Ecto logs a query at debug, so development keeps info.
config :logger, level: :info
