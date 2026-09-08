# The ephemeral cluster starts before ExUnit; it stops when the VM exits.
# Migrations arrive with the packages that own them: at S0 there are none.
Turnstile.Test.Cluster.start(
  otp_app: :turnstile_core,
  repos: [
    {Turnstile.TestRepos.Sandboxed, role: :app, database: :sandboxed},
    {Turnstile.TestRepos.Committed, role: :app, database: :committed, pool_size: 2},
    {Turnstile.TestRepos.Owner, role: :owner, database: :committed, pool_size: 2}
  ],
  migrate: fn _owner_repo -> :ok end
)

ExUnit.start(exclude: [:committed, :tripwire])
