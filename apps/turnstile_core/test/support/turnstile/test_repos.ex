defmodule Turnstile.TestRepos do
  @moduledoc """
  The three repos of core's own test run: the application role on the
  sandboxed database, the application role on the committed database, and
  the owner role on the committed database. Test support only; a thin
  application runs its own repos.
  """

  use Boundary, top_level?: true, deps: [Ecto, Ecto.Adapters.Postgres, Ecto.Adapters.SQL]
end

defmodule Turnstile.TestRepos.Sandboxed do
  @moduledoc "The application-role repo on the sandboxed database, one transaction per test."
  use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
end

defmodule Turnstile.TestRepos.Committed do
  @moduledoc "The application-role repo on the committed database, for tests that need real commits."
  use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
end

defmodule Turnstile.TestRepos.Owner do
  @moduledoc "The owner-role repo on the committed database, for the library's own writes and truncation."
  use Ecto.Repo, otp_app: :turnstile_core, adapter: Ecto.Adapters.Postgres
end
