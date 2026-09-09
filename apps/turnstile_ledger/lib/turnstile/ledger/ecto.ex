defmodule Turnstile.Ledger.Ecto do
  @moduledoc """
  The ledger as a table in the application's own database, so a fact write
  and the events that describe it commit together or not at all.

  An append takes as many positions as it has events from the counter row in
  one statement, stamps them, and inserts the rows in the transaction the
  write is already in. Nothing else assigns a position, so the positions of
  two concurrent appends never overlap and a reader that knows the head
  knows what it is waiting for. A read is `position > from` in position
  order; the head is the counter row, which is ahead of the events of a
  transaction that has not committed yet, and never behind them.

  The tuple a configuration carries is
  `{Turnstile.Ledger.Ecto, repo: MyApp.Repo, owner_repo: MyApp.OwnerRepo}`.
  """

  @behaviour Turnstile.Ledger

  use Boundary, top_level?: true, deps: [Ecto, Turnstile, Turnstile.Ledger.Dialect], exports: [Counter, Row, Value]

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Dialect.Postgres
  alias Turnstile.Ledger.Ecto.Counter
  alias Turnstile.Ledger.Ecto.Row

  @exemption {:exempt, :library}

  @schema NimbleOptions.new!(
            repo: [
              type: :atom,
              required: true,
              doc: "The application-role repo whose transaction the events commit with."
            ],
            owner_repo: [
              type: :atom,
              required: true,
              doc: "The owner-role repo genesis, reconcile, and the catalog check run through."
            ],
            dialect: [
              type: :atom,
              doc:
                "The `Turnstile.Ledger.Dialect` implementation for this database. " <>
                  "`dialect/1` answers the Postgres one when the options name none, " <>
                  "and it reads that name when it runs, so this module compiles without it."
            ],
            lock: [
              type: {:or, [:string, nil]},
              default: "FOR UPDATE",
              doc: "The clause a fact row is re-read under before a write."
            ]
          )

  @doc "The schema of the ledger's options. Fields: #{NimbleOptions.docs(@schema)}"
  @impl Turnstile.Ledger
  def options_schema, do: @schema

  @impl Turnstile.Ledger
  def append(options, []) when is_list(options), do: {:ok, []}

  def append(options, events) when is_list(options) and is_list(events) do
    repo = repo(options)
    dialect = dialect(options)

    transactional(repo, fn ->
      with {:ok, last} <- dialect.take(repo, counter!(), length(events)) do
        stamped = stamp(events, last - length(events) + 1)
        :ok = write(repo, stamped, dialect.fact_insert_batch())
        {:ok, stamped}
      end
    end)
  end

  @impl Turnstile.Ledger
  def read(options, from, limit) when is_list(options) and is_integer(from) and is_integer(limit) do
    read_by(dialect(options).reader(), repo(options), from, limit)
  end

  @impl Turnstile.Ledger
  def head(options) when is_list(options) do
    name = counter!()
    query = from(c in Counter, where: c.name == ^name)

    case repo(options).one(query, turnstile: @exemption) do
      %Counter{position: position} -> {:ok, position}
      nil -> {:error, engine(:head, "no counter row named #{inspect(name)}")}
    end
  end

  @doc """
  The events at position zero, the genesis backfill. A read answers with what
  lies above a position and zero is the lowest position there is, so the
  origin is read on its own, in id order, by a reader that wants the whole
  ledger. A ledger with no genesis answers with nothing.
  """
  @spec origin(keyword()) :: {:ok, [FactEvent.t()]} | {:error, Error.Engine.t()}
  def origin(options) when is_list(options) do
    query = from(r in Row, where: r.position == 0, order_by: [asc: r.id])

    query
    |> repo(options).all(turnstile: @exemption)
    |> events()
  end

  @doc """
  Run `fun` with the counter row locked, and answer what it answered. Every
  append inside it is ordered against every other appender, so a caller that
  reads the ledger and then appends what the read implies, as publishing a
  policy version does, sees no other append in between.
  """
  @spec transaction(keyword(), (-> result)) :: result when result: term()
  def transaction(options, fun) when is_list(options) and is_function(fun, 0) do
    repo = repo(options)

    transactional(repo, fn ->
      _locked = lock_counter(repo, options)
      fun.()
    end)
  end

  @doc """
  Insert events whose positions are already stamped, in the dialect's
  batches, through the given repo. Genesis writes its events at position
  zero through the owner repo this way; an append writes its own.
  """
  @spec write(module(), [FactEvent.t()], pos_integer()) :: :ok
  def write(repo, events, batch) when is_atom(repo) and is_list(events) and is_integer(batch) do
    events
    |> Enum.map(&Row.dump/1)
    |> Enum.chunk_every(batch)
    |> Enum.each(fn rows -> {_count, nil} = repo.insert_all(Row, rows, turnstile: @exemption) end)
  end

  @doc "How many events the table holds, read through the given repo."
  @spec count(module()) :: non_neg_integer()
  def count(repo) when is_atom(repo) do
    repo.aggregate(Row, :count, turnstile: @exemption)
  end

  @doc "The repo the options name."
  @spec repo(keyword()) :: module()
  def repo(options) when is_list(options), do: Keyword.fetch!(options, :repo)

  @doc "The dialect the options name, or the default one."
  @spec dialect(keyword()) :: module()
  def dialect(options) when is_list(options), do: Keyword.get(options, :dialect, Postgres)

  @doc "The clause a fact row is re-read under, from the options."
  @spec lock(keyword()) :: String.t() | nil
  def lock(options) when is_list(options), do: Keyword.get(options, :lock, "FOR UPDATE")

  @doc "The name of the counter row this process takes positions from."
  @spec counter!() :: String.t()
  def counter! do
    case Config.resolve() do
      {:ok, config} -> config.ledger_counter
      {:error, error} -> raise error
    end
  end

  defp read_by(:counter_row, repo, from, limit) do
    query = from(r in Row, where: r.position > ^from, order_by: [asc: r.position, asc: r.id], limit: ^limit)

    query
    |> repo.all(turnstile: @exemption)
    |> events()
  end

  defp events(rows) do
    loaded =
      Enum.reduce_while(rows, {:ok, []}, fn row, {:ok, done} ->
        case Row.load(row) do
          {:ok, event} -> {:cont, {:ok, [event | done]}}
          {:error, error} -> {:halt, {:error, engine(:read, Exception.message(error))}}
        end
      end)

    case loaded do
      {:ok, done} -> {:ok, Enum.reverse(done)}
      {:error, error} -> {:error, error}
    end
  end

  defp lock_counter(repo, options) do
    name = counter!()
    query = from(c in Counter, where: c.name == ^name)
    repo.one(%{query | lock: lock(options)}, turnstile: @exemption)
  end

  defp stamp(events, first) do
    events
    |> Enum.with_index(first)
    |> Enum.map(fn {event, position} -> %{event | position: position} end)
  end

  # The append joins the write's transaction when there is one, and opens one
  # otherwise, so the events of a single-row write commit with the row and an
  # append on its own is still atomic.
  defp transactional(repo, fun) do
    if repo.in_transaction?(), do: fun.(), else: unwrap(repo, repo.transaction(fun))
  end

  defp unwrap(_repo, {:ok, result}), do: result
  defp unwrap(_repo, {:error, %Error.Engine{} = error}), do: {:error, error}
  defp unwrap(repo, {:error, reason}), do: {:error, engine(:append, "#{inspect(repo)} rolled back: #{inspect(reason)}")}

  defp engine(operation, detail), do: %Error.Engine{adapter: __MODULE__, operation: operation, detail: detail}
end
