defmodule ExampleCerbos.Repo.Migrations.Rules do
  @moduledoc false
  use Ecto.Migration

  # The rules of this binding are the policy files under `priv/policies`,
  # which a sidecar reads and evaluates, so there is nothing about them for
  # the database to hold: no policy, no role beyond the two the domain
  # migration makes, no column. The migration is here so that the set of
  # migrations reads the same across the bindings and so that the schema
  # dump this application commits is the tables of the example and the
  # ledger and nothing else, which is what makes the diff a check that the
  # rules moved out of the database rather than a gap in the record.
  def up, do: :ok
  def down, do: :ok
end
