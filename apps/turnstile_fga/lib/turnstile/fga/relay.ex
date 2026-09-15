defmodule Turnstile.Fga.Relay do
  @moduledoc """
  Batched, ordered delivery from a Postgres table. One runner per job, a
  cursor that says how far that runner has got, and a wake-up for the
  process that wrote a row and does not want to wait for the next tick.

  The shape is the same wherever records are produced faster than they can
  be shipped: rows go into a table in the same transaction as the work that
  produced them, and something else reads them afterwards, in order, and
  hands them to whatever is slow. What is slow is a `Turnstile.Fga.Relay.Job`,
  which says how to read a batch above a position and what delivering one
  means. Nothing here knows what a row holds.

  A pass runs in one transaction: it takes an advisory lock on the runner's
  name, so a second node steps aside rather than delivering the same rows
  twice; reads a batch above the cursor; delivers it; advances the cursor;
  and commits. Delivery that fails rolls the pass back, the cursor stays
  where it was, and the batch is read again on the next pass. That is
  at-least-once delivery in position order, and a job's `c:Turnstile.Fga.Relay.Job.deliver/3`
  is written to accept a batch it has seen before.

  An application puts one of these in its supervision tree:

      {Turnstile.Fga.Relay,
       runners: [
         [name: :markers, repo: MyApp.Repo, job: MyApp.Markers, batch: 500]
       ]}

  and calls `wake/1` after a write that produced rows. A test drives
  `drain_once/1` instead of starting anything. `options_schema/0` is the
  option list a runner takes.

  The repo a runner is given is one whose calls carry no decision: a plain
  Ecto repo, or a repo the seam knows as the owner's. The cursor states
  nothing about a subject or an object, so there is no decision to carry,
  and the rows a job reads are the application's to place where its own
  rules allow.
  """

  use Boundary,
    top_level?: true,
    deps: [Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [Cursor, Entry, Job, Options, Pass]

  use Supervisor

  alias Turnstile.Fga.Relay.Adapter.Drain
  alias Turnstile.Fga.Relay.Adapter.Runner
  alias Turnstile.Fga.Relay.Options
  alias Turnstile.Fga.Relay.Pass

  @supervisor_schema NimbleOptions.new!(
                       runners: [
                         type: {:list, :keyword_list},
                         required: true,
                         doc: "One option list per runner, each as `options_schema/0` gives."
                       ],
                       name: [type: :atom, doc: "The name the supervisor itself is registered under."]
                     )

  @doc "The options one runner takes. Fields: #{NimbleOptions.docs(Options.schema())}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: Options.schema()

  @doc "Start a supervisor over the runners named. Options: #{NimbleOptions.docs(@supervisor_schema)}"
  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(options) when is_list(options) do
    options = NimbleOptions.validate!(options, @supervisor_schema)
    {name, options} = Keyword.pop(options, :name)
    Supervisor.start_link(__MODULE__, options, if(name, do: [name: name], else: []))
  end

  @doc """
  Drain the runner's rows once, now, and answer what the pass did. This is
  what a runner's tick calls, and what a test calls in place of starting
  one. Options: `options_schema/0`.
  """
  @spec drain_once(keyword()) :: {:ok, Pass.t()} | {:error, term()}
  def drain_once(options) when is_list(options), do: Drain.once(Options.validate!(options))

  @doc """
  Ask a runner to pass now rather than at its next tick, from the process
  that wrote the rows. It answers `:ok` without waiting for the pass, so a
  writer's transaction is not held open by delivery. The runner is a pid, or
  the name a registered one was started under.
  """
  @spec wake(GenServer.server()) :: :ok
  def wake(runner), do: Runner.wake(runner)

  @impl Supervisor
  def init(options) do
    children = Enum.map(options[:runners], &{Runner, &1})
    Supervisor.init(children, strategy: :one_for_one)
  end
end
