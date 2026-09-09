defmodule Turnstile.Fga.Projector.Scheduler do
  @moduledoc """
  Drains the projection the adapter declares, once every `drain_interval`
  milliseconds, and emits what each drain applied on
  `[:turnstile, :fga, :drain]`, so what watches the lag reads it there. The
  process holds the projector it resolved and answers no call: what it knows,
  it emits.

  It is started unnamed and takes nothing: what it drains with is the
  configuration entry and the binding, which a thin application has in place
  before its supervisor starts, so the child specification is the module.

      children = [Example.Repo, Turnstile.Fga.Projector.Scheduler]

  An interval of its own and the delay before the first drain are for a test
  that starts one: the interval is the entry's `drain_interval` otherwise,
  which is where a deployment sets it.

  A drain that fails is emitted and left to the next interval. The checkpoint
  is exact wherever a drain stopped, so the next drain reads from there and
  converges, and a store that refused a write is not helped by writing to it
  sooner.

  Nothing drives this process from a test. A test that wants a drain calls
  `c:Turnstile.Projection.drain_once/1` on the projector, or
  `Turnstile.Test.settle/0` where
  it wants every event of the ledger covered.
  """

  use GenServer

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Fga
  alias Turnstile.Projection.Drain

  @event [:turnstile, :fga, :drain]

  @schema NimbleOptions.new!(
            interval: [
              type: :pos_integer,
              doc: "Milliseconds between drains; the entry's `drain_interval` when absent."
            ],
            first: [type: :non_neg_integer, doc: "Milliseconds before the first drain; the interval when absent."]
          )

  @doc "The telemetry event every drain emits."
  @spec event() :: [atom()]
  def event, do: @event

  @doc "Start a scheduler. Options: #{NimbleOptions.docs(@schema)}"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options \\ []) when is_list(options) do
    {server, options} = Keyword.split(options, [:name])
    GenServer.start_link(__MODULE__, NimbleOptions.validate!(options, @schema), server)
  end

  @doc "Drain once now, emit what it applied, and answer it, without waiting for an interval."
  @spec drain(module(), struct()) :: {:ok, Drain.t()} | {:error, Error.Engine.t()}
  def drain(module, projector) when is_atom(module) do
    result = module.drain_once(projector)
    :ok = emit(result)
    result
  end

  @impl GenServer
  def init(options) do
    case Fga.projection() do
      {:ok, {module, projector}} -> {:ok, state(options, module, projector), {:continue, :first}}
      {:error, error} -> {:stop, error}
    end
  end

  @impl GenServer
  def handle_continue(:first, state) do
    _timer = Process.send_after(self(), :drain, state.first)
    {:noreply, state}
  end

  @impl GenServer
  def handle_info(:drain, state) do
    _result = drain(state.module, state.projector)
    _timer = Process.send_after(self(), :drain, state.interval)
    {:noreply, state}
  end

  defp state(options, module, projector) do
    interval = options[:interval] || interval()

    %{module: module, projector: projector, interval: interval, first: options[:first] || interval}
  end

  defp interval do
    {:ok, config} = Config.resolve()
    {_adapter, options} = Config.adapter(config)

    Keyword.fetch!(options, :drain_interval)
  end

  defp emit({:ok, %Drain{} = drain}) do
    :telemetry.execute(@event, %{applied: drain.applied, from: drain.from, to: drain.to}, %{drain: drain})
  end

  defp emit({:error, error}) do
    :telemetry.execute(@event, %{applied: 0, from: 0, to: 0}, %{error: error})
  end
end
