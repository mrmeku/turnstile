defmodule Turnstile.Fga.Outbox do
  @moduledoc """
  The markers a drain works from: one row per object whose tuples may have
  fallen behind the tables, written in the transaction that changed them.

  `attach/0` puts a handler on `Turnstile.Change.event()`. The handler asks
  the bound mapping which objects a change can have affected and inserts a
  marker for each, on the connection the change was made on. A change that
  does not commit takes its markers with it, and a marker that commits is
  delivered at least once. A marker says which object to look at and nothing
  more: what that object requires is read from the tables when the marker is
  delivered, so a marker delivered twice costs a read and no write.

  Delivery is a `Turnstile.Relay.Job`. One pass reads a batch of markers
  above the cursor, takes the distinct objects in it, brings the store to
  what the tables require for each, and deletes the markers it delivered,
  all in the pass's transaction. A pass that does not commit leaves the
  markers and the cursor where they were. A thin application puts the runner
  in its tree and gives the job no options of its own:

      {Turnstile.Relay,
       runners: [
         [name: Turnstile.Fga.Outbox.runner(), repo: MyApp.Repo, job: Turnstile.Fga.Outbox]
       ]}

  The store a pass writes is the one the configuration names, resolved on
  the pass rather than named by the runner, and the tables it reads are read
  on the pass's own connection, so the tuples it writes are the tuples those
  rows require at the moment they are read.

  A marker names an object and says nothing about who may reach it, so
  writes to this table carry the library exemption rather than a decision.

  A handler that raises is detached by `:telemetry`, and a detached handler
  is a store that falls behind in silence. The handler here answers `:ok`
  whatever happens and reports a failure as `unmarked_event/0` instead. The
  change itself is not lost: the insert runs in the write's transaction, so
  a failed insert takes the write down with it, and a failure before the
  insert leaves the change unmarked, which is drift `Turnstile.Fga.reconcile/0`
  reports.
  """

  @behaviour Turnstile.Relay.Job

  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Change
  alias Turnstile.Error
  alias Turnstile.Fga.Adapter.Store
  alias Turnstile.Fga.Binding
  alias Turnstile.Relay.Entry
  alias Turnstile.Relay.Job

  @exemption {:exempt, :library}
  @handler {__MODULE__, :change}
  @runner :turnstile_fga
  @table "turnstile_fga_outbox"
  @unmarked [:turnstile, :fga, :unmarked]

  @schema NimbleOptions.new!([])

  schema @table do
    field(:object, :string)
  end

  @type t :: %__MODULE__{}

  @doc "The name the cursor is kept under, which the runner a thin application starts must also use."
  @spec runner() :: atom()
  def runner, do: @runner

  @doc "The table the markers are written to."
  @spec table() :: String.t()
  def table, do: @table

  @doc "The event the handler emits for a change it could not mark, carrying the change and the exception."
  @spec unmarked_event() :: [atom()]
  def unmarked_event, do: @unmarked

  @doc "Mark every change from now on. Calling this twice leaves one handler."
  @spec attach() :: :ok
  def attach do
    case :telemetry.attach(@handler, Change.event(), &__MODULE__.__change__/4, nil) do
      :ok -> :ok
      {:error, :already_exists} -> :ok
    end
  end

  @doc "Stop marking changes."
  @spec detach() :: :ok
  def detach do
    _detached = :telemetry.detach(@handler)
    :ok
  end

  @doc "Mark these objects, so the next drain brings the store to what their rows require."
  @spec mark(module(), [String.t()]) :: :ok
  def mark(repo, objects) when is_atom(repo) and is_list(objects) do
    case Enum.map(objects, &%{object: &1}) do
      [] -> :ok
      rows -> marked(repo, rows)
    end
  end

  @doc false
  @spec __change__([atom()], map(), map(), term()) :: :ok
  def __change__(_event, _measurements, change, _config) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} -> mark(binding.repo, binding.mapping.changed(binding.repo, change))
      {:error, %Error{} = error} -> raise error
    end
  rescue
    exception ->
      :telemetry.execute(@unmarked, %{}, %{change: change, exception: exception})
      :ok
  end

  @impl Job
  def options_schema, do: @schema

  @impl Job
  def read(repo, _options, from, limit) do
    query = from(marker in __MODULE__, where: marker.id > ^from, order_by: [asc: marker.id], limit: ^limit)

    entries =
      for marker <- repo.all(query, turnstile: @exemption), do: %Entry{position: marker.id, payload: marker.object}

    {:ok, entries}
  end

  @impl Job
  def deliver(repo, _options, entries) do
    objects =
      entries
      |> Enum.map(& &1.payload)
      |> Enum.uniq()

    with {:ok, store} <- Store.configured(),
         :ok <- Store.converge(%{store | repo: repo}, objects) do
      forget(repo, entries)
    end
  end

  defp marked(repo, rows) do
    {_written, nil} = repo.insert_all(__MODULE__, rows, turnstile: @exemption)
    :ok
  end

  defp forget(repo, entries) do
    positions = Enum.map(entries, & &1.position)
    delivered = from(marker in __MODULE__, where: marker.id in ^positions)
    {_deleted, nil} = repo.delete_all(delivered, turnstile: @exemption)

    :ok
  end
end
