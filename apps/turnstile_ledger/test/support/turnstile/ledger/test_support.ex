defmodule Turnstile.Ledger.TestSupport do
  @moduledoc """
  What the ledger's own suite needs beside its repos and its migrations: the
  ledger tuples the tests configure, the fixture population the shape tests
  write, a dialect whose write returns no rows, the reporter the review task
  runs, and the truncation a committed test ends with.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Ecto,
      Ecto.Adapters.SQL,
      Turnstile,
      Turnstile.Facts,
      Turnstile.Fixture,
      Turnstile.Ledger.Dialect,
      Turnstile.Ledger.Ecto,
      Turnstile.Ledger.Review,
      Turnstile.Test,
      Turnstile.Test.Sandbox
    ],
    exports: [Boot, Committed, Dialect, Golden, Measure, Population, Review, Shape]
end

defmodule Turnstile.Ledger.TestSupport.Boot do
  @moduledoc """
  What every test in this package starts with: a connection, a counter row,
  a clock that answers, and a configuration naming the ledger under test.
  A test tagged `:committed`, or the tripwire, which times a real write,
  writes for real on the committed database, takes positions from the
  `default` row, and empties both tables when it ends; every other test runs
  inside the sandbox with a counter row of its own.
  """

  alias Turnstile.Adapter
  alias Turnstile.Ledger
  alias Turnstile.Ledger.TestRepos
  alias Turnstile.Ledger.TestSupport.Committed
  alias Turnstile.Test.Clock.Mock
  alias Turnstile.Test.Sandbox

  @doc """
  Call from `setup`. Answers the ledger under test, the repo the test writes
  through, and the name of the counter row its positions come from. Pass
  `ledger` to configure another ledger, `:none` among them.
  """
  @spec setup(map(), Turnstile.Config.ledger() | nil) :: {:ok, keyword()}
  def setup(tags, ledger \\ nil) when is_map(tags) do
    repo = repo(tags)
    ledger = ledger || ledger(tags)
    :ok = connect(tags, repo)
    Mox.stub(Mock, :now, &DateTime.utc_now/0)
    :ok = Turnstile.Test.with_config(adapter: Adapter.Fake, ledger: ledger, clock: Mock)
    {:ok, ledger: ledger, repo: repo, counter: Ledger.Ecto.counter!()}
  end

  @doc "The repo a test with these tags writes through."
  @spec repo(map()) :: module()
  def repo(tags) when is_map(tags), do: if(committed?(tags), do: TestRepos.CommittedApp, else: TestRepos.App)

  @doc "Whether these tags ask for the committed database: a committed test, and the tripwire, which times a real write."
  @spec committed?(map()) :: boolean()
  def committed?(tags) when is_map(tags), do: Enum.any?([:committed, :tripwire], &tags[&1])

  @doc "The ledger a test with these tags configures."
  @spec ledger(map()) :: {module(), keyword()}
  def ledger(tags) when is_map(tags) do
    if committed?(tags) do
      Committed.ledger()
    else
      {Ledger.Ecto, repo: TestRepos.App, owner_repo: TestRepos.App}
    end
  end

  defp connect(tags, repo) do
    if committed?(tags) do
      :ok = Committed.truncate!()
      ExUnit.Callbacks.on_exit(&Committed.truncate!/0)
    else
      Sandbox.setup(repo, tags)
    end
  end
end

defmodule Turnstile.Ledger.TestSupport.Dialect do
  @moduledoc """
  A dialect whose write cannot return its rows, which is what a database
  without `RETURNING` answers. Everything else is Postgres's, so a test can
  ask what the bulk API does when the one thing it needs is missing.
  """

  @behaviour Turnstile.Ledger.Dialect

  alias Turnstile.Ledger.Dialect
  alias Turnstile.Ledger.Dialect.Postgres

  @impl Dialect
  def rows_back, do: :select

  @impl Dialect
  def fact_insert_batch, do: Postgres.fact_insert_batch()

  @impl Dialect
  def reader, do: Postgres.reader()

  @impl Dialect
  def lock_clause, do: Postgres.lock_clause()

  @impl Dialect
  def take(repo, counter, count), do: Postgres.take(repo, counter, count)

  @impl Dialect
  def append_only_grant(events, app_role), do: Postgres.append_only_grant(events, app_role)

  @impl Dialect
  def cascades(repo, tables), do: Postgres.cascades(repo, tables)
end

defmodule Turnstile.Ledger.TestSupport.Population do
  @moduledoc """
  The rows the shape tests measure against: accounts with no clearance yet,
  folders with no fact of their own, and memberships that are grants. Every
  insert goes through the bulk API under an exemption, so the ledger records
  the population as it records anything else and the shapes measured
  afterwards start from a ledger that agrees with the tables.
  """

  alias Turnstile.Facts
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Membership

  @exemption {:exempt, "shape fixture"}

  @doc "The exemption every fixture write declares."
  @spec exemption() :: {:exempt, String.t()}
  def exemption, do: @exemption

  @doc "Insert `count` accounts with no clearance, named `account-<n>`, and answer their ids."
  @spec accounts!(module(), pos_integer()) :: [String.t()]
  def accounts!(repo, count) when is_atom(repo) and is_integer(count) do
    entries = Enum.map(1..count, &%{id: id(&1), clearance: nil})
    {:ok, _record} = Facts.bulk_insert(Account, entries, repo: repo, turnstile: @exemption)
    Enum.map(entries, & &1.id)
  end

  @doc "Insert `count` folders, which declare no fact, and answer their ids."
  @spec folders!(module(), pos_integer()) :: [pos_integer()]
  def folders!(repo, count) when is_atom(repo) and is_integer(count) do
    entries = Enum.map(1..count, &%{name: "folder #{&1}"})
    {:ok, record} = Facts.bulk_insert(Folder, entries, repo: repo, turnstile: @exemption)
    ^count = record.count
    Enum.map(repo.all(Folder, turnstile: @exemption), & &1.id)
  end

  @doc "Grant every account the reader role on the folder, and answer how many grants that was."
  @spec memberships!(module(), [String.t()], pos_integer()) :: pos_integer()
  def memberships!(repo, accounts, folder) when is_atom(repo) and is_list(accounts) do
    entries = Enum.map(accounts, &%{account_id: &1, folder_id: folder, role: :reader})
    {:ok, record} = Facts.bulk_insert(Membership, entries, repo: repo, turnstile: @exemption)
    record.count
  end

  @doc "The account id for a number, in the form the population uses."
  @spec id(pos_integer()) :: String.t()
  def id(number) when is_integer(number), do: "account-" <> String.pad_leading(Integer.to_string(number), 5, "0")
end

defmodule Turnstile.Ledger.TestSupport.Review do
  @moduledoc """
  The reporter `mix turnstile.review` runs in this package's own test: two
  subjects and what they may do, fixed, because the table's shape is what the
  task is being held to here. A thin application's reporter asks the port.
  """

  @behaviour Turnstile.Ledger.Review

  alias Turnstile.Ledger.Review.Row

  @impl Turnstile.Ledger.Review
  def rows(options) do
    [
      %Row{subject: "account-00001", kind: :user, operation: :read, object: "folder:1", note: "reader"},
      %Row{subject: "account-00002", kind: :privileged, operation: :edit, object: "folder:1", note: note(options)}
    ]
  end

  defp note(options), do: if(options[:at], do: "as of #{options[:at]}", else: "editor")
end

defmodule Turnstile.Ledger.TestSupport.Shape do
  @moduledoc """
  What a shape test counts: each query of a call by what it was on rather
  than by its text, and the audit records of one bulk write, found by the
  operation id the write answered with, so the records of another async
  test are never counted as this one's.
  """

  alias Turnstile.Facts
  alias Turnstile.Facts.Record

  @kinds [
    {~r/FOR UPDATE$/, :locked_select},
    {~r/^UPDATE turnstile_ledger_counter/, :take},
    {~r/^INSERT INTO "turnstile_ledger_events"/, :events},
    {~r/^SELECT/, :select},
    {~r/^UPDATE/, :update},
    {~r/^INSERT/, :insert},
    {~r/^DELETE/, :delete}
  ]

  @doc "Route the bulk API's span to the calling process for the rest of the test."
  @spec listen() :: :ok
  def listen do
    handler = :telemetry_test.attach_event_handlers(self(), Facts.events())
    ExUnit.Callbacks.on_exit(fn -> :telemetry.detach(handler) end)
    :ok
  end

  @doc "The kind of each query, in the order the queries ran."
  @spec kinds([String.t()]) :: [atom()]
  def kinds(queries) when is_list(queries), do: Enum.map(queries, &kind/1)

  @doc "The audit records the write with this operation id emitted, in order."
  @spec records(String.t()) :: [Record.t()]
  def records(operation_id) when is_binary(operation_id), do: collect(operation_id, [])

  defp kind(query) do
    {_pattern, kind} = Enum.find(@kinds, {nil, :other}, fn {pattern, _kind} -> Regex.match?(pattern, query) end)
    kind
  end

  defp collect(operation_id, done) do
    receive do
      {[:turnstile, :bulk, :stop], _ref, _measurements, %{record: %Record{operation_id: ^operation_id} = record}} ->
        collect(operation_id, [record | done])

      {[:turnstile, :bulk, _suffix], _ref, _measurements, _metadata} ->
        collect(operation_id, done)
    after
      0 -> Enum.reverse(done)
    end
  end
end

defmodule Turnstile.Ledger.TestSupport.Committed do
  @moduledoc """
  What a committed test ends with: the fixture tables, the events table, and
  the counter row put back the way the run found them, through the owner-role
  repo. A committed test writes for real, so nothing else cleans up after it.
  """

  alias Ecto.Adapters.SQL
  alias Turnstile.Ledger.TestRepos

  @tables ~w(turnstile_fixture_memberships turnstile_fixture_items turnstile_fixture_folders
             turnstile_fixture_accounts turnstile_ledger_events)

  @doc "The ledger tuple a committed test configures: the application role writing, the owner role reading."
  @spec ledger() :: {module(), keyword()}
  def ledger do
    {Turnstile.Ledger.Ecto, repo: TestRepos.CommittedApp, owner_repo: TestRepos.CommittedOwner}
  end

  @doc "Empty the fixture and the events table and reset the `default` counter row."
  @spec truncate!() :: :ok
  def truncate! do
    _result = SQL.query!(TestRepos.CommittedOwner, "TRUNCATE #{Enum.join(@tables, ", ")} RESTART IDENTITY CASCADE")

    _result =
      SQL.query!(TestRepos.CommittedOwner, "UPDATE turnstile_ledger_counter SET position = 0 WHERE name = $1", [
        "default"
      ])

    :ok
  end
end

defmodule Turnstile.Ledger.TestSupport.Golden do
  @moduledoc """
  A committed file and the output a test holds beside it. Where what a
  mechanism answers with is text, the file is the assertion: the test reads
  it and compares, and a run with `TURNSTILE_UPDATE_GOLDEN=1` writes the file
  instead, so a change of shape is read as a diff like any other change.
  """

  @variable "TURNSTILE_UPDATE_GOLDEN"

  @doc "The golden file's content, written from `actual` first when the run was asked to update it."
  @spec read!(Path.t(), String.t()) :: String.t()
  def read!(path, actual) when is_binary(path) and is_binary(actual) do
    if System.get_env(@variable) == "1" do
      File.mkdir_p!(Path.dirname(path))
      File.write!(path, actual)
    end

    File.read!(path)
  end
end

defmodule Turnstile.Ledger.TestSupport.Measure do
  @moduledoc """
  Where a measurement goes: to standard output, and nowhere near an
  assertion. The cost of serializing on the counter row and the time the
  tripwire took are numbers a reader of the run wants and a gate must never
  turn on, so they are printed and left there.
  """

  @doc "Print a measurement. The test logger sits at warning, so this is what a reader of the run sees."
  @spec report(String.t()) :: :ok
  # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
  def report(text) when is_binary(text), do: IO.puts(text)
end
