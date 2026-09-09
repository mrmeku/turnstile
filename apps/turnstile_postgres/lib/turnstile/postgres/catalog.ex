defmodule Turnstile.Postgres.Catalog do
  @moduledoc """
  What the database says its own rules are. `read!/1` asks `pg_policy` for
  every policy on the bound tables, with the `USING` and `WITH CHECK`
  expressions as `pg_get_expr/2` renders them, asks `pg_depend` for the
  columns those expressions reference, and asks the migrations table for
  the highest version, which is the version a decision names.

  `load!/1` reads once per binding and keeps the result for the life of the
  VM, so no call on the request path pays for a catalog read and the query
  counts of a mediated call stay what the shape tests expect. An
  application loads it at boot through `Turnstile.Postgres.load!/0`, after
  the binding; `current!/1` loads on first use for a caller that did not.

  Every statement runs through the bound repo's raw channel under the
  library exemption, so a catalog read is mediated like any other call.
  """

  alias Turnstile.Error
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Name
  alias Turnstile.Postgres.Policy

  @exemption {:exempt, :library}

  @policies """
  SELECT p.polname, c.relname, p.polcmd::text,
         pg_get_expr(p.polqual, p.polrelid),
         pg_get_expr(p.polwithcheck, p.polrelid)
  FROM pg_policy p
  JOIN pg_class c ON c.oid = p.polrelid
  WHERE c.relname = ANY($1)
  ORDER BY c.relname, p.polname
  """

  @columns """
  SELECT referenced.relname, attribute.attname
  FROM pg_depend dependency
  JOIN pg_policy policy ON dependency.classid = 'pg_policy'::regclass AND dependency.objid = policy.oid
  JOIN pg_class protected ON protected.oid = policy.polrelid
  JOIN pg_class referenced
    ON dependency.refclassid = 'pg_class'::regclass AND dependency.refobjid = referenced.oid
  JOIN pg_attribute attribute
    ON attribute.attrelid = dependency.refobjid AND attribute.attnum = dependency.refobjsubid
  WHERE dependency.refobjsubid > 0 AND protected.relname = ANY($1)
  ORDER BY 1, 2
  """

  @enforce_keys [:version, :policies, :columns]
  defstruct @enforce_keys

  @typedoc "The version, the policies of the bound tables, and the table and column of every read they make."
  @type t :: %__MODULE__{version: String.t(), policies: [Policy.t()], columns: [{String.t(), String.t()}]}

  @doc "Read the catalog now, whatever a previous call loaded."
  @spec read!(Binding.t()) :: t()
  def read!(%Binding{repo: repo} = binding) do
    tables = Binding.tables(binding)

    %__MODULE__{
      version: version!(repo, binding.migrations_table),
      policies: policies!(repo, tables),
      columns: Enum.map(rows(repo, @columns, [tables]), &column/1)
    }
  end

  @doc "The policies on those tables, as `pg_policy` holds them, for a caller with no binding yet."
  @spec policies!(module(), [String.t()]) :: [Policy.t()]
  def policies!(repo, tables) when is_atom(repo) and is_list(tables) do
    Enum.map(rows(repo, @policies, [tables]), &policy/1)
  end

  @doc "Read the catalog once for this binding and keep it; a second call reads nothing."
  @spec load!(Binding.t()) :: t()
  def load!(%Binding{} = binding) do
    case :persistent_term.get({__MODULE__, binding}, nil) do
      %__MODULE__{} = loaded ->
        loaded

      nil ->
        catalog = read!(binding)
        :persistent_term.put({__MODULE__, binding}, catalog)
        catalog
    end
  end

  @doc "The loaded catalog, loading it on first use."
  @spec current!(Binding.t()) :: t()
  def current!(%Binding{} = binding), do: load!(binding)

  @doc "The scope policy of an operation on a table, or `nil`."
  @spec scope(t(), String.t(), atom()) :: Policy.t() | nil
  def scope(%__MODULE__{} = catalog, table, operation) do
    named(catalog, table, Policy.scope_name(Atom.to_string(operation)))
  end

  @doc "The gate policy of an operation on a table, or `nil`."
  @spec gate(t(), String.t(), atom()) :: Policy.t() | nil
  def gate(%__MODULE__{} = catalog, table, operation) do
    named(catalog, table, Policy.gate_name(Atom.to_string(operation)))
  end

  @doc "The policies as the text a policy version carries."
  @spec to_text([Policy.t()]) :: String.t()
  def to_text(policies) when is_list(policies), do: Enum.map_join(policies, "", &Policy.to_text/1)

  defp named(%__MODULE__{policies: policies}, table, name) do
    Enum.find(policies, &(&1.table == table and &1.name == name))
  end

  defp policy([name, table, command, using, with_check]) do
    %Policy{name: name, table: table, command: Policy.command(command), using: using, with_check: with_check}
  end

  defp column([table, name]), do: {table, name}

  defp version!(repo, table) do
    case rows(repo, "SELECT max(version)::text FROM #{Name.check!(table, :migrations_table)}", []) do
      [[version]] when is_binary(version) -> version
      _empty -> raise Error.Invalid, what: :catalog, detail: "#{table} holds no migration version"
    end
  end

  defp rows(repo, statement, params) do
    %{rows: rows} = repo.query!(statement, params, turnstile: @exemption)
    rows
  end
end
