defmodule Turnstile.Fga.Relay.Adapter.Runner do
  @moduledoc false
  # The worker: one process per runner, a timer, and the wake-up.
  #
  # It holds no state a caller needs and answers no call. Each tick runs one
  # pass and asks the arithmetic in `Turnstile.Fga.Relay.Core.Backoff` when the
  # next one is due: at once where a batch was full, after the idle interval
  # where it was not, and after a growing wait where the pass failed.
  #
  # A wake-up is a cast, so the process that wrote the rows is not held up
  # by a delivery, and it cancels the timer and passes at once. While a pass
  # is pending the runner carries no timer, and a wake-up that arrives then
  # is dropped rather than queueing a second pass: the pending pass reads
  # everything committed before it runs, which is everything a wake-up
  # arriving now is about. A wake-up that arrives during a pass is handled
  # after it, where a timer is set again, so the rows that landed mid-pass
  # go out at once rather than at the next tick.
  #
  # The process is registered under the runner's name unless the options say
  # otherwise, so `Turnstile.Fga.Relay.wake/1` takes that name, and a test starts
  # one unregistered and wakes it by pid.

  use GenServer

  alias Turnstile.Fga.Relay.Adapter.Drain
  alias Turnstile.Fga.Relay.Core.Backoff
  alias Turnstile.Fga.Relay.Options

  @enforce_keys [:options, :failures, :timer]
  defstruct @enforce_keys

  @type t :: %__MODULE__{options: keyword(), failures: non_neg_integer(), timer: reference() | nil}

  @doc "One child per runner, identified by the runner's name."
  @spec child_spec(keyword()) :: Supervisor.child_spec()
  def child_spec(options) when is_list(options) do
    %{id: {__MODULE__, options[:name]}, start: {__MODULE__, :start_link, [options]}}
  end

  @doc "Start a runner. Options: `Turnstile.Fga.Relay.options_schema/0`."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(options) when is_list(options) do
    options = Options.validate!(options)
    GenServer.start_link(__MODULE__, options, registration(options))
  end

  @doc "Ask a runner to pass now. Answers without waiting for the pass."
  @spec wake(GenServer.server()) :: :ok
  def wake(runner), do: GenServer.cast(runner, :wake)

  @impl GenServer
  def init(options) do
    {:ok, %__MODULE__{options: options, failures: 0, timer: nil}, {:continue, :first}}
  end

  @impl GenServer
  def handle_continue(:first, %__MODULE__{} = state) do
    {:noreply, scheduled(state, state.options[:first] || state.options[:idle])}
  end

  @impl GenServer
  def handle_cast(:wake, %__MODULE__{timer: nil} = state), do: {:noreply, state}

  def handle_cast(:wake, %__MODULE__{} = state) do
    _left = Process.cancel_timer(state.timer)
    send(self(), :pass)

    {:noreply, %{state | timer: nil}}
  end

  @impl GenServer
  def handle_info(:pass, %__MODULE__{} = state) do
    result = Drain.once(state.options)
    wait = Backoff.wait(result, state.failures, state.options)
    state = %{state | failures: Backoff.failures(result, state.failures)}

    {:noreply, scheduled(state, wait)}
  end

  defp scheduled(%__MODULE__{} = state, wait), do: %{state | timer: Process.send_after(self(), :pass, wait)}

  defp registration(options), do: if(options[:register], do: [name: options[:name]], else: [])
end
