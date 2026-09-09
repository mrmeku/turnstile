defmodule Example.Repo do
  @moduledoc "The application-role repo: every query on a protected schema carries a decision or an exemption."

  use Ecto.Repo, otp_app: :turnstile_example, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo
end
