defmodule Turnstile.Postgres.Replay do
  @moduledoc """
  A policy version put back, in a database of its own.

  The version of this adapter is the migration number, and its content is
  the policies as `pg_get_expr` renders them. A rendered expression names
  the schema it reads, `public.<table>`, so the same expression written into
  a second schema of the same database would still read the first: putting a
  version back takes a database, not a schema. Raising that database and
  running the migrations on it belongs to whoever asks; this function makes
  the result the past.

  Three steps, in this order.

  1. The tables the version's policies protect stop forcing row-level
     security, so the owner role can write state that no policy admits.
  2. The rows of the tables the caller names are copied from one connection
     to the other, table by table, in the order the caller gives, which is
     the order the foreign keys allow. Then the caller's own writer runs,
     which is where the difference between the tables and a fold goes.
  3. The policies on the protected tables are dropped, the version's are
     created in their place, and those tables force row-level security
     again.

  What comes back is a database whose state is the state that was written
  and whose rules are the version's, so a question asked there is answered
  by the rules of that version. Sequences are left where the migrations put
  them, because a replay asks and writes nothing.
  """

  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Name
  alias Turnstile.Postgres.Policy

  @exemption {:exempt, :library}

  @doc """
  Build the past in the database `to:` points at. Requires `tables:`, the
  tables whose rows are copied, in the order the foreign keys allow;
  `from:` and `to:`, two instances of the repo, the one read and the one
  written; and `policies:`, the text of the version to put back. Takes
  `state:`, a function called with the version's policies not yet in force,
  where a caller writes what the tables do not hold.
  """
  @spec build!(module(), keyword()) :: :ok
  def build!(repo, options) when is_atom(repo) and is_list(options) do
    policies = Policy.from_text(Keyword.fetch!(options, :policies))
    protected = protected(policies)
    to = Keyword.fetch!(options, :to)

    on(repo, to, fn -> Enum.each(protected, &force!(repo, &1, "NO FORCE")) end)
    state!(repo, options)
    on(repo, to, fn -> rules!(repo, policies, protected) end)
  end

  # The rows the tables hold, then whatever the caller writes over them.
  defp state!(repo, options) do
    tables = Enum.map(Keyword.fetch!(options, :tables), &Name.check!(&1, :table))
    to = Keyword.fetch!(options, :to)
    Enum.each(tables, &copy!(repo, &1, Keyword.fetch!(options, :from), to))
    on(repo, to, Keyword.get(options, :state, fn -> :ok end))
    :ok
  end

  # The version's policies where the ones the migrations wrote were.
  defp rules!(repo, policies, protected) do
    Enum.each(Catalog.policies!(repo, protected), &drop!(repo, &1))
    Enum.each(policies, &create!(repo, &1))
    Enum.each(protected, &force!(repo, &1, "FORCE"))
  end

  defp protected(policies) do
    policies
    |> Enum.map(& &1.table)
    |> Enum.uniq()
    |> Enum.sort()
    |> Enum.map(&Name.check!(&1, :table))
  end

  defp copy!(repo, table, from, to) do
    %{columns: columns, rows: rows} = on(repo, from, fn -> run!(repo, "SELECT * FROM #{table}") end)
    names = Enum.map_join(columns, ", ", &Name.check!(&1, :column))
    places = Enum.map_join(1..length(columns)//1, ", ", &"$#{&1}")
    statement = "INSERT INTO #{table} (#{names}) VALUES (#{places})"
    on(repo, to, fn -> Enum.each(rows, &run!(repo, statement, &1)) end)
  end

  defp drop!(repo, %Policy{} = policy) do
    _dropped = run!(repo, "DROP POLICY #{Name.check!(policy.name, :policy)} ON #{Name.check!(policy.table, :table)}")
    :ok
  end

  defp create!(repo, %Policy{} = policy) do
    _created = run!(repo, Policy.to_sql(policy))
    :ok
  end

  defp force!(repo, table, clause) do
    _altered = run!(repo, "ALTER TABLE #{table} #{clause} ROW LEVEL SECURITY")
    :ok
  end

  defp run!(repo, statement, params \\ []), do: repo.query!(statement, params, turnstile: @exemption)

  # The instance in force for the length of the function, and what was in
  # force put back after it, so a caller that pointed the repo somewhere
  # finds it there still.
  defp on(repo, instance, fun) do
    previous = repo.put_dynamic_repo(instance)

    try do
      fun.()
    after
      repo.put_dynamic_repo(previous)
    end
  end
end
