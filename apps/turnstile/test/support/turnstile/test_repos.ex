defmodule Turnstile.TestRepos do
  @moduledoc """
  The repos of this repository's own runs: the application role on the
  sandboxed database, the application role on the committed database, the
  owner role on the committed database, and the repo the schema-dump test
  hands to its own cluster. A thin application runs its own repos instead.
  """

  use Boundary,
    top_level?: true,
    deps: [Ecto, Ecto.Adapters.Postgres, Ecto.Adapters.SQL, Turnstile],
    exports: [Committed, Dump, Owner, Sandboxed]
end

defmodule Turnstile.TestRepos.Sandboxed do
  @moduledoc "The application-role repo on the sandboxed database, one transaction per test."
  use Ecto.Repo, otp_app: :turnstile, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo
end

defmodule Turnstile.TestRepos.Committed do
  @moduledoc "The application-role repo on the committed database, for tests that need real commits."
  use Ecto.Repo, otp_app: :turnstile, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo
end

defmodule Turnstile.TestRepos.Owner do
  @moduledoc "The owner-role repo on the committed database, for the library's own writes and truncation."
  use Ecto.Repo, otp_app: :turnstile, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo, role: :owner
end

defmodule Turnstile.TestRepos.Dump do
  @moduledoc "The owner-role repo the schema-dump test names; it runs in the dump's own cluster."
  use Ecto.Repo, otp_app: :turnstile, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo, role: :owner
end
