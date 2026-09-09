defmodule ExampleCerbos.Repo.Migrations.Genesis do
  @moduledoc false
  use Ecto.Migration

  alias Turnstile.Ledger.Genesis

  # The backfill runs in every ledger mode, from the migration after the one
  # that creates the events table: on a database whose tables are still empty
  # it writes nothing, and on one carrying facts from before the ledger it
  # writes each of them at position zero. Only the owner repo is named, which
  # is the one repo the schema dump's cluster starts.
  def up do
    {:ok, _count} = Genesis.run([owner_repo: Example.OwnerRepo], Example.schemas(), migration: __MODULE__)
    :ok
  end

  def down, do: :ok
end
