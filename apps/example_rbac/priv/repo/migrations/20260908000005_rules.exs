defmodule ExampleRbac.Repo.Migrations.Rules do
  @moduledoc false
  use Ecto.Migration

  # The rules of this binding are `ExampleRbac.Policy`, a module the adapter
  # evaluates in the application, so there is nothing about them for the
  # database to hold: no policy, no role beyond the two the domain migration
  # makes, no column. The migration is here so that the set of migrations
  # reads the same across the bindings and so that the schema dump this
  # application commits is the tables of the example and nothing else, which
  # is what makes the diff a check that the rules are in code rather than a
  # gap in the record.
  def up, do: :ok
  def down, do: :ok
end
