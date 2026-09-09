defmodule Example.OwnerRepo do
  @moduledoc "The owner-role repo: migrations, the ledger's own writes, and truncation between committed tests."

  use Ecto.Repo, otp_app: :turnstile_example, adapter: Ecto.Adapters.Postgres
  use Turnstile.Repo, role: :owner
end
