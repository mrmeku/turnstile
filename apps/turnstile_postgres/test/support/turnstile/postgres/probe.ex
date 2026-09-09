defmodule Turnstile.Postgres.Probe do
  @moduledoc """
  Tables of its own for the cases the fixture cannot carry: one with a
  policy that reads a column no declaration names and a policy that reads a
  table no bound schema names, and one shaped like a migrations table that
  holds no version. Writing either policy on a fixture table would widen
  what the fixture's own scenarios read, so the probe keeps its own tables
  and the fixture's are left as the conformance migration wrote them.
  """

  use Boundary, top_level?: true, deps: [Ecto, Turnstile, Turnstile.Postgres], exports: [Row]

  alias Turnstile.Postgres.Migration

  @table "turnstile_probe_rows"
  @versions "turnstile_probe_versions"
  @undeclared "current_setting('turnstile.probe', true) = label"
  @unbound """
  EXISTS (SELECT 1 FROM turnstile_fixture_accounts a
          WHERE a.id = current_setting('turnstile.probe', true))
  """

  @doc "The table shaped like a migrations table that never had a migration run against it."
  @spec empty_versions() :: String.t()
  def empty_versions, do: @versions

  @doc "Create the tables and the policies, through an owner-role repo."
  @spec create!(module()) :: :ok
  def create!(repo) when is_atom(repo) do
    _rows = repo.query!("CREATE TABLE #{@table} (id bigserial PRIMARY KEY, label text)")
    _versions = repo.query!("CREATE TABLE #{@versions} (version bigint PRIMARY KEY)")
    :ok = Migration.grant!(repo, table: @versions, to: "turnstile_app", commands: [:select])
    :ok = Migration.protect!(repo, @table)
    :ok = Migration.policy!(repo, table: @table, operation: :read, using: @undeclared)
    :ok = Migration.policy!(repo, table: @table, operation: :sighted, using: @unbound)
    Migration.grant!(repo, table: @table, to: "turnstile_app", commands: [:select])
  end
end

defmodule Turnstile.Postgres.Probe.Row do
  @moduledoc "The probe's schema: a primary key it declares and a label it does not."

  use Ecto.Schema
  use Turnstile.Schema

  @type t :: %__MODULE__{}

  schema "turnstile_probe_rows" do
    field(:label, :string)
  end

  object_type(:probe_row)
end
