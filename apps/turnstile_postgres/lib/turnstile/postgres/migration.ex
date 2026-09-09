defmodule Turnstile.Postgres.Migration do
  @moduledoc """
  The helpers a migration calls. This is the only place the package writes
  DDL, and every statement runs through the repo the caller passes, under
  the library exemption, so a migration is mediated like any other call.

  - `protect!/2` enables row-level security on a table and forces it, so
    the policies apply to the table's owner as well as to everyone else.
  - `policy!/2` adds the `SELECT` policy of one operation. The helper
    writes the operation guard itself,
    `current_setting('turnstile.operation', true) = '<operation>'`, and
    joins the caller's expression to it. Permissive policies combine with
    OR, so without the guard the policy of one operation would widen
    another; with it, only the policy of the operation in force can hold.
  - `gate!/2` adds the `UPDATE` policy of one operation: the `USING`
    expression an answer reads before a write, and the `WITH CHECK`
    expression the database applies to the write itself. A gate carries no
    operation guard, so the database refuses a write that violates it
    whether or not anything asked first.
  - `admit!/2` adds a permissive `true` policy for one command. Forcing
    row-level security refuses every statement no policy admits, so a table
    whose rows are inserted or deleted outside a decision needs one.
  - `exempt!/2` adds the policy that admits one role's statements while no
    operation is in force, which is what the seam leaves behind when it
    admits a call outside a decision. A role whose reads are unfiltered
    whatever the settings say takes the same policy without that clause.
  - `grant!/2` grants a role the table privileges it needs. Row-level
    security narrows what a role may reach; the grant is what lets it reach
    the table at all, and the two are set together.
  - `publish!/2` reads the policies back from `pg_policy` and appends the
    policy version, in the transaction the migration is already running in.

  Every name a helper puts into a statement passes
  `Turnstile.Postgres.Name.check!/2` first. An expression is written by
  whoever writes the migration and reaches the database as given.
  """

  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Name
  alias Turnstile.Postgres.Policy
  alias Turnstile.Postgres.Version

  @exemption {:exempt, :library}
  @content_bytes 65_536
  @commands ~w(select insert update delete)a
  @guard "current_setting('turnstile.operation', true)"

  @doc "Enable row-level security on the table and force it on the table's owner too."
  @spec protect!(module(), String.t() | atom()) :: :ok
  def protect!(repo, table) when is_atom(repo) do
    name = Name.check!(table, :table)
    run!(repo, "ALTER TABLE #{name} ENABLE ROW LEVEL SECURITY")
    run!(repo, "ALTER TABLE #{name} FORCE ROW LEVEL SECURITY")
  end

  @doc "Add the `SELECT` policy of one operation. Requires `table:`, `operation:`, and `using:`."
  @spec policy!(module(), keyword()) :: :ok
  def policy!(repo, options) when is_atom(repo) and is_list(options) do
    table = Name.check!(Keyword.fetch!(options, :table), :table)
    operation = Name.check!(Keyword.fetch!(options, :operation), :operation)
    using = Keyword.fetch!(options, :using)
    name = Name.check!(Policy.scope_name(operation), :policy)

    run!(
      repo,
      "CREATE POLICY #{name} ON #{table} FOR SELECT USING (#{@guard} = '#{operation}' AND (#{using}))"
    )
  end

  @doc "Add the `UPDATE` gate of one operation. Requires `table:`, `operation:`, `using:`, and `with_check:`."
  @spec gate!(module(), keyword()) :: :ok
  def gate!(repo, options) when is_atom(repo) and is_list(options) do
    table = Name.check!(Keyword.fetch!(options, :table), :table)
    operation = Name.check!(Keyword.fetch!(options, :operation), :operation)
    name = Name.check!(Policy.gate_name(operation), :policy)
    using = Keyword.fetch!(options, :using)
    with_check = Keyword.fetch!(options, :with_check)

    run!(repo, "CREATE POLICY #{name} ON #{table} FOR UPDATE USING (#{using}) WITH CHECK (#{with_check})")
  end

  @doc "Add a permissive `true` policy for one command. Requires `table:` and `command:`."
  @spec admit!(module(), keyword()) :: :ok
  def admit!(repo, options) when is_atom(repo) and is_list(options) do
    table = Name.check!(Keyword.fetch!(options, :table), :table)
    command = Keyword.fetch!(options, :command)
    {clause, shape} = shape(command, "true")
    name = Name.check!("turnstile_admit_#{command}", :policy)
    run!(repo, "CREATE POLICY #{name} ON #{table} FOR #{clause} #{shape}")
  end

  @doc """
  Add the policy that admits a role's statements outside a decision.
  Requires `table:` and `to:`; takes `commands:`, every command by
  default, and `outside_decision:`, `false` where the role holds the
  policy whatever operation is in force.
  """
  @spec exempt!(module(), keyword()) :: :ok
  def exempt!(repo, options) when is_atom(repo) and is_list(options) do
    table = Name.check!(Keyword.fetch!(options, :table), :table)
    role = Name.check!(Keyword.fetch!(options, :to), :role)
    predicate = exemption(role, Keyword.get(options, :outside_decision, true))

    Enum.each(Keyword.get(options, :commands, @commands), fn command ->
      {clause, shape} = shape(command, predicate)
      name = Name.check!("turnstile_exempt_#{role}_#{command}", :policy)
      run!(repo, "CREATE POLICY #{name} ON #{table} FOR #{clause} #{shape}")
    end)
  end

  @doc "Grant a role privileges on a table. Requires `table:`, `to:`, and `commands:`."
  @spec grant!(module(), keyword()) :: :ok
  def grant!(repo, options) when is_atom(repo) and is_list(options) do
    table = Name.check!(Keyword.fetch!(options, :table), :table)
    role = Name.check!(Keyword.fetch!(options, :to), :role)
    commands = Keyword.fetch!(options, :commands)
    granted = Enum.map_join(commands, ", ", &granted/1)
    run!(repo, "GRANT #{granted} ON #{table} TO #{role}")
  end

  @doc """
  Read the policies on those tables back and append the policy version.
  Requires `tables:`, `version:`, `author:`, and `approval:`; takes
  `ledger:`, `at:`, and `content_bytes:`. The ledger is passed rather than
  resolved, because a migration runs before the configuration is booted.
  """
  @spec publish!(module(), keyword()) :: PolicyVersion.t()
  def publish!(repo, options) when is_atom(repo) and is_list(options) do
    tables = Enum.map(Keyword.fetch!(options, :tables), &Name.check!(&1, :table))
    policies = Catalog.policies!(repo, tables)
    version = Version.of(Turnstile.Postgres, policies, published(options))
    {:ok, _result} = Version.publish(version, Keyword.get(options, :ledger, :none))
    version
  end

  defp published(options) do
    [
      version: Keyword.fetch!(options, :version),
      author: Keyword.fetch!(options, :author),
      approval: Keyword.fetch!(options, :approval),
      at: Keyword.get_lazy(options, :at, &DateTime.utc_now/0),
      content_bytes: Keyword.get(options, :content_bytes, @content_bytes)
    ]
  end

  defp exemption(role, true), do: "current_user = '#{role}' AND coalesce(#{@guard}, '') = ''"
  defp exemption(role, false), do: "current_user = '#{role}'"

  defp granted(:select), do: "SELECT"
  defp granted(:insert), do: "INSERT"
  defp granted(:update), do: "UPDATE"
  defp granted(:delete), do: "DELETE"

  defp shape(:insert, predicate), do: {"INSERT", "WITH CHECK (#{predicate})"}
  defp shape(:delete, predicate), do: {"DELETE", "USING (#{predicate})"}
  defp shape(:select, predicate), do: {"SELECT", "USING (#{predicate})"}
  defp shape(:update, predicate), do: {"UPDATE", "USING (#{predicate}) WITH CHECK (#{predicate})"}

  defp run!(repo, statement) do
    _result = repo.query!(statement, [], turnstile: @exemption)
    :ok
  end
end
