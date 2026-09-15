defmodule Turnstile.Relay.TestJob do
  @moduledoc """
  The job this package proves itself over: rows in one table, delivery into
  another. It writes its own population as well, so the tests run against
  it with no fixture beside it.

  A delivery lands one row per entry, keyed by the runner and the position,
  and a repeat lands nothing, which is what a job written for at-least-once
  delivery does at the far end. The table it delivers into carries a serial
  of its own, so a test reads the order deliveries arrived in as well as
  what arrived.
  """

  @behaviour Turnstile.Relay.Job

  use Boundary, top_level?: true, deps: [Ecto, NimbleOptions, Turnstile.Relay], exports: [Row, Sent]

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Relay.Entry
  alias Turnstile.Relay.Job
  alias Turnstile.Relay.TestJob.Row
  alias Turnstile.Relay.TestJob.Sent

  @default "default"
  @exemption {:exempt, :library}

  @schema NimbleOptions.new!(
            runner: [
              type: :string,
              default: @default,
              doc: "Which population this job reads, so two runners in one database do not meet."
            ],
            tag: [type: :string, default: "sent", doc: "What a delivered row is marked with."]
          )

  @doc "The population `write/2` writes and the default the options carry."
  @spec default() :: String.t()
  def default, do: @default

  @impl Job
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @impl Job
  @spec read(module(), keyword(), non_neg_integer(), pos_integer()) :: {:ok, [Entry.t()]}
  def read(repo, options, from, limit) do
    query =
      from(row in Row,
        where: row.runner == ^options[:runner] and row.id > ^from,
        order_by: [asc: row.id],
        limit: ^limit,
        select: %{position: row.id, body: row.body}
      )

    {:ok, Enum.map(repo.all(query, turnstile: @exemption), &%Entry{position: &1.position, payload: &1.body})}
  end

  @impl Job
  @spec deliver(module(), keyword(), [Entry.t()]) :: :ok
  def deliver(repo, options, entries) do
    rows = Enum.map(entries, &%{runner: options[:runner], position: &1.position, tag: options[:tag]})
    options = [on_conflict: :nothing, conflict_target: [:runner, :position], turnstile: @exemption]
    {_count, nil} = repo.insert_all(Sent, rows, options)

    :ok
  end

  @doc "Write `count` rows into the default population, above every position already there."
  @spec write(module(), pos_integer()) :: :ok
  def write(repo, count), do: write(repo, @default, count)

  @doc "Write `count` rows into one population, above every position already there."
  @spec write(module(), String.t(), pos_integer()) :: :ok
  def write(repo, runner, count) when is_binary(runner) and count > 0 do
    rows = Enum.map(1..count, &%{runner: runner, body: "row-#{&1}"})
    {^count, nil} = repo.insert_all(Row, rows, turnstile: @exemption)

    :ok
  end

  @doc "What reached the far end for one population, in the order it arrived."
  @spec arrived(module(), String.t()) :: [non_neg_integer()]
  def arrived(repo, runner) when is_binary(runner) do
    query = from(sent in Sent, where: sent.runner == ^runner, order_by: [asc: sent.id], select: sent.position)

    repo.all(query, turnstile: @exemption)
  end
end

defmodule Turnstile.Relay.TestJob.Row do
  @moduledoc "A row on its way out, whose serial is the position that orders it."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "turnstile_relay_test_rows" do
    field :runner, :string
    field :body, :string
  end
end

defmodule Turnstile.Relay.TestJob.Sent do
  @moduledoc "A row that reached the far end, once per runner and position."
  use Ecto.Schema

  @type t :: %__MODULE__{}

  schema "turnstile_relay_test_sent" do
    field :runner, :string
    field :position, :integer
    field :tag, :string
  end
end
