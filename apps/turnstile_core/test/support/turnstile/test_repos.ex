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
