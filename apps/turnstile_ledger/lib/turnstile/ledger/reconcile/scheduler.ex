defmodule Turnstile.Ledger.Reconcile.Scheduler do
  @moduledoc """
  Runs `Turnstile.Ledger.Reconcile.run/2` on an interval and emits what it
  found on `[:turnstile, :ledger, :reconcile]`, with the drift in the
  metadata and the sizes as measurements, so the organization's log pipeline
  and whatever watches it decide what a difference means. The process holds
  no state a caller needs and answers no call: what it knows, it emits.

  It is started unnamed, with its ledger, its schemas, its interval, and its
  clock passed in, so a test can start one of its own and drive it, and an
  application can run one per node under its supervisor.

      {Turnstile.Ledger.Reconcile.Scheduler,
       ledger: [repo: ExampleRbac.Repo, owner_repo: ExampleRbac.OwnerRepo],
       schemas: [ExampleRbac.Assignment, ExampleRbac.User],
       interval: :timer.minutes(15)}

  The interval is the window `docs/reference.md` §10's claim names: drift
  from outside the seam is detected within it.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Ledger.Reconcile]
  use GenServer

  alias Turnstile.Ledger.Reconcile
  alias Turnstile.Projection.Drift

  @event [:turnstile, :ledger, :reconcile]

  @schema NimbleOptions.new!(
            ledger: [type: :keyword_list, required: true, doc: "The options of the `Turnstile.Ledger.Ecto` ledger."],
            schemas: [type: {:list, :atom}, required: true, doc: "The schemas whose facts are compared."],
            interval: [type: :pos_integer, required: true, doc: "Milliseconds between passes."],
            first: [type: :non_neg_integer, doc: "Milliseconds before the first pass; the interval when absent."]
          )

  @doc "The telemetry event every pass emits."
  @spec event() :: [atom()]
  def event, do: @event

  @doc "Start a scheduler. Options: #{NimbleOptions.docs(@schema)}"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) when is_list(options) do
    {server, options} = Keyword.split(options, [:name])
    GenServer.start_link(__MODULE__, NimbleOptions.validate!(options, @schema), server)
  end

  @doc "Run one pass now and answer what it found, without waiting for the interval."
  @spec pass(keyword()) :: {:ok, Drift.t()} | {:error, Turnstile.Error.Engine.t()}
  def pass(options) when is_list(options) do
    result = Reconcile.run(options[:ledger], options[:schemas])
    :ok = emit(result)
    result
  end

  @impl GenServer
  def init(options) do
    {:ok, options, {:continue, :first}}
  end

  @impl GenServer
  def handle_continue(:first, options) do
    _timer = Process.send_after(self(), :pass, options[:first] || options[:interval])
    {:noreply, options}
  end

  @impl GenServer
  def handle_info(:pass, options) do
    _result = pass(options)
    _timer = Process.send_after(self(), :pass, options[:interval])
    {:noreply, options}
  end

  defp emit({:ok, %Drift{} = drift}) do
    measurements = %{missing: length(drift.missing), extra: length(drift.extra), checked_to: drift.checked_to}
    :telemetry.execute(@event, measurements, %{drift: drift, clean?: Drift.clean?(drift)})
  end

  defp emit({:error, error}) do
    :telemetry.execute(@event, %{missing: 0, extra: 0, checked_to: 0}, %{error: error})
  end
end
