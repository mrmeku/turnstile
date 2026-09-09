defmodule Turnstile.Ledger.Catalog do
  @moduledoc """
  The check that nothing changes a fact row behind the ledger's back. A
  foreign key into a fact schema's table with `ON DELETE CASCADE` or
  `ON DELETE SET NULL` lets the database remove a grant, or blank the column
  that names its subject or its object, when the row it references goes, and
  no fact event says it happened: the ledger and the tables part company
  with no write to blame. Genesis runs this check before it writes anything,
  and a conformance case fails a migration that adds one.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Ledger.Dialect]

  alias Turnstile.Error
  alias Turnstile.Ledger.Dialect
  alias Turnstile.Ledger.Dialect.Cascade
  alias Turnstile.Schema

  @doc "Answer `:ok`, or the constraint that would change a fact row with no event for it."
  @spec check(module(), [module()], module()) :: :ok | {:error, Error.Invalid.t() | Error.Engine.t()}
  def check(owner_repo, schemas, dialect \\ Dialect.Postgres)
      when is_atom(owner_repo) and is_list(schemas) and is_atom(dialect) do
    with {:ok, cascades} <- dialect.cascades(owner_repo, tables(schemas)) do
      refuse(cascades)
    end
  end

  @doc "The tables of the fact schemas among the given schemas."
  @spec tables([module()]) :: [String.t()]
  def tables(schemas) when is_list(schemas) do
    schemas
    |> Enum.filter(&Schema.fact_schema?/1)
    |> Enum.map(& &1.__schema__(:source))
  end

  defp refuse([]), do: :ok

  defp refuse(cascades) do
    {:error, %Error.Invalid{what: :cascade, detail: Enum.map_join(cascades, "; ", &detail/1)}}
  end

  defp detail(%Cascade{} = cascade) do
    "#{cascade.constraint} on #{cascade.table} #{acts(cascade.action)} a fact row when a row of " <>
      "#{cascade.referenced} goes, and no fact event would say so"
  end

  defp acts(:delete), do: "deletes"
  defp acts(:blank), do: "blanks"
end
