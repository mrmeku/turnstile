defmodule Turnstile.Dev.TestRepos do
  @moduledoc """
  The repos of this package's own run: the application role on the
  sandboxed database, the application role on the committed database, the
  owner role on the committed database, and the repo the schema-dump test
  hands to its own cluster. Plain repos: the seam is core's, and this
  package proves the cluster and the dump, not the seam.
  """

  use Boundary,
    top_level?: true,
    deps: [Ecto, Ecto.Adapters.Postgres, Ecto.Adapters.SQL],
    exports: [Committed, Dump, Owner, Sandboxed]
end

defmodule Turnstile.Dev.TestRepos.Sandboxed do
  @moduledoc "The application-role repo on the sandboxed database, one transaction per test."
  use Ecto.Repo, otp_app: :turnstile_dev, adapter: Ecto.Adapters.Postgres
end

defmodule Turnstile.Dev.TestRepos.Committed do
  @moduledoc "The application-role repo on the committed database."
  use Ecto.Repo, otp_app: :turnstile_dev, adapter: Ecto.Adapters.Postgres
end

defmodule Turnstile.Dev.TestRepos.Owner do
  @moduledoc "The owner-role repo on the committed database."
  use Ecto.Repo, otp_app: :turnstile_dev, adapter: Ecto.Adapters.Postgres
end

defmodule Turnstile.Dev.TestRepos.Dump do
  @moduledoc "The owner-role repo the schema-dump test names; it runs in the dump's own cluster."
  use Ecto.Repo, otp_app: :turnstile_dev, adapter: Ecto.Adapters.Postgres
end
