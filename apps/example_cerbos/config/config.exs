import Config

# The sidecar the adapter asks, the policy directory that sidecar reads, and
# the commit that directory is at. The commit is the version identifier every
# decision names, and it comes from the repository the policies were merged
# in, which is what POLICY_COMMIT carries in a deployment.
config :example_cerbos,
  address: "127.0.0.1:3592",
  policies: "priv/policies",
  commit: System.get_env("POLICY_COMMIT", "policies-at-the-working-tree")

if config_env() == :test do
  import_config "test.exs"
end
