defmodule Turnstile.Ledger.Dialect do
  @moduledoc """
  What the ledger's storage does differently from one database to the next,
  in seven callbacks. The ledger itself has one shape; a dialect answers how
  this database gives rows back from a bulk write, how many events go in one
  insert, how a reader knows it sees every committed position, how positions
  are taken, what clause locks a row for a re-read, which grants make the
  events table append-only for the application role, and how the catalog is
  asked for foreign keys that would delete or blank a fact row behind the
  ledger's back.

  `Turnstile.Ledger.Dialect.Postgres` is the implementation this repository
  ships. A second database is a second module: nothing else in the ledger
  names a dialect's SQL.
  """

  use Boundary, top_level?: true, deps: [Turnstile], exports: [Cascade, Postgres]

  alias Turnstile.Error

  @typedoc "Whether a bulk write can return the rows it wrote, or whether they are selected separately."
  @type rows_back :: :returning | :select

  @typedoc "How a reader knows the positions it sees are every committed one below the head."
  @type reader :: :counter_row

  @doc "Whether a bulk write returns the rows it touched."
  @callback rows_back() :: rows_back()

  @doc "How many events go into one insert."
  @callback fact_insert_batch() :: pos_integer()

  @doc "The reader's strategy."
  @callback reader() :: reader()

  @doc """
  Take `count` positions from the counter row named `counter`, in one
  statement, and answer the last of them: the events being appended hold
  the positions from `last - count + 1` to `last`. An absent row is an
  engine failure, not a row created on the spot: the row is the migration's
  and the grant on it is `UPDATE`.
  """
  @callback take(repo :: module(), counter :: String.t(), count :: pos_integer()) ::
              {:ok, pos_integer()} | {:error, Error.Engine.t()}

  @doc "The clause a fact row is re-read under before a write, or `nil` where the database has none."
  @callback lock_clause() :: String.t() | nil

  @doc "The statements that let the application role add events to `events` and never change or remove one."
  @callback append_only_grant(events :: String.t(), app_role :: String.t()) :: [String.t()]

  @doc "The foreign keys into `tables` that delete or blank a row when their referenced row goes."
  @callback cascades(repo :: module(), tables :: [String.t()]) :: {:ok, [Cascade.t()]} | {:error, Error.Engine.t()}
end

defmodule Turnstile.Ledger.Dialect.Cascade do
  @moduledoc "One foreign key that would change a fact row without a fact event: the constraint, the table it is on, the table it references, and what it does."

  @enforce_keys [:constraint, :table, :referenced, :action]
  defstruct @enforce_keys

  @type action :: :delete | :blank

  @type t :: %__MODULE__{constraint: String.t(), table: String.t(), referenced: String.t(), action: action()}
end
