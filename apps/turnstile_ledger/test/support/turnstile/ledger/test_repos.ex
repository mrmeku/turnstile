defmodule Turnstile.Ledger.TestRepos do
  @moduledoc "The repos of the ledger's own test run: the owner role and the application role on the sandboxed database, the owner role on the committed database, and the repo the schema-dump test hands to its own cluster."

  use Boundary, top_level?: true, deps: [Ecto, Ecto.Adapters.Postgres, Ecto.Adapters.SQL, Turnstile]
end

defmodule Turnstile.Ledger.TestRepos.Owner do
  @moduledoc "The owner-role repo on the sandboxed database."
  use Ecto.Repo, otp_app: :turnstile_ledger, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo, role: :owner
end

defmodule Turnstile.Ledger.TestRepos.App do
  @moduledoc "The application-role repo on the sandboxed database, one transaction per test."
  use Ecto.Repo, otp_app: :turnstile_ledger, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo
end

defmodule Turnstile.Ledger.TestRepos.CommittedOwner do
  @moduledoc "The owner-role repo on the committed database, where a migration can be run down and up for real."
  use Ecto.Repo, otp_app: :turnstile_ledger, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo, role: :owner
end

defmodule Turnstile.Ledger.TestRepos.Dump do
  @moduledoc "The owner-role repo the schema-dump test names; it runs in the dump's own cluster."
  use Ecto.Repo, otp_app: :turnstile_ledger, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo, role: :owner
end
