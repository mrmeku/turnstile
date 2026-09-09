defmodule Turnstile.Ledger.Dialect.Postgres do
  @moduledoc """
  The dialect for PostgreSQL. A bulk write returns the rows it touched, so
  the values before and after a change are read in the same statement that
  makes it. Positions are taken in one `UPDATE ... RETURNING`, which locks
  the counter row for the rest of the transaction and serializes appenders
  against one another. Because that row hands out every position, a reader
  that has seen the head can read `WHERE position > $1 ORDER BY position`
  and know it is missing nothing once the transactions below the head have
  committed.
  """

  @behaviour Turnstile.Ledger.Dialect

  alias Ecto.Adapters.SQL
  alias Turnstile.Error
  alias Turnstile.Ledger.Dialect
  alias Turnstile.Ledger.Dialect.Cascade

  @counter "turnstile_ledger_counter"

  @cascades """
  SELECT c.conname::text, r.relname::text, f.relname::text, c.confdeltype::text
  FROM pg_constraint c
  JOIN pg_class r ON r.oid = c.conrelid
  JOIN pg_class f ON f.oid = c.confrelid
  WHERE c.contype = 'f' AND c.confdeltype IN ('c', 'n') AND r.relname = ANY($1)
  ORDER BY 1
  """

  @impl Dialect
  def rows_back, do: :returning

  @impl Dialect
  def fact_insert_batch, do: 2_000

  @impl Dialect
  def reader, do: :counter_row

  @impl Dialect
  def lock_clause, do: "FOR UPDATE"

  @impl Dialect
  def take(repo, counter, count) when is_atom(repo) and is_binary(counter) and is_integer(count) and count > 0 do
    sql = "UPDATE #{@counter} SET position = position + $2 WHERE name = $1 RETURNING position"

    case SQL.query(repo, sql, [counter, count]) do
      {:ok, %{rows: [[position]]}} -> {:ok, position}
      {:ok, %{rows: []}} -> {:error, engine(:take, "no counter row named #{inspect(counter)}")}
      {:error, error} -> {:error, engine(:take, Exception.message(error))}
    end
  end

  @impl Dialect
  def append_only_grant(events, app_role) when is_binary(events) and is_binary(app_role) do
    [
      "GRANT SELECT, INSERT ON #{events} TO #{app_role}",
      "GRANT USAGE, SELECT ON SEQUENCE #{events}_id_seq TO #{app_role}"
    ]
  end

  @impl Dialect
  def cascades(repo, tables) when is_atom(repo) and is_list(tables) do
    case SQL.query(repo, @cascades, [tables]) do
      {:ok, %{rows: rows}} -> {:ok, Enum.map(rows, &cascade/1)}
      {:error, error} -> {:error, engine(:cascades, Exception.message(error))}
    end
  end

  defp cascade([constraint, table, referenced, action]) do
    %Cascade{constraint: constraint, table: table, referenced: referenced, action: action(action)}
  end

  defp action("c"), do: :delete
  defp action("n"), do: :blank

  defp engine(operation, detail) do
    %Error.Engine{adapter: __MODULE__, operation: operation, detail: detail}
  end
end
