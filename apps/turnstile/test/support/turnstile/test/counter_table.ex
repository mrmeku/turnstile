defmodule Turnstile.Test.CounterTable do
  @moduledoc """
  The counter table for core's own test run. Core cannot depend on
  `turnstile_ledger`, whose migration helper is the table's source of truth,
  because the ledger depends on core and an umbrella refuses the cycle even
  when one edge is test-only; so core's suite creates the same table here,
  and the freeze test holds its columns to the committed list.
  """

  use Boundary, top_level?: true, deps: []

  @doc "Creates the table, its `default` row at 0, and the application role's grants, through an owner-role repo."
  @spec create!(module()) :: :ok
  def create!(repo) when is_atom(repo) do
    repo.query!("CREATE TABLE turnstile_ledger_counter (name text PRIMARY KEY, position bigint NOT NULL)")
    repo.query!("INSERT INTO turnstile_ledger_counter (name, position) VALUES ('default', 0)")
    repo.query!("GRANT SELECT, INSERT, UPDATE ON turnstile_ledger_counter TO turnstile_app")
    :ok
  end
end
