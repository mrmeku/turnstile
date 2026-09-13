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
