defmodule Example.Siem do
  @moduledoc """
  The example's consumer of the library's three events: a process that
  maps every decision event, every change event, and every access event to
  an OCSF record and holds the result in memory.

  A deployment sends those records to its security log. Holding them in a
  list keeps the mapping under test without putting a schema version in a
  published package; the mapping itself is this package's own and answers
  from the payload alone.

  Records arrive as casts and are read as calls, so a caller that caused
  an event reads its own records afterwards. The thin application starts
  one at boot; a test starts its own, unattached, and feeds it payloads.
  """

  use GenServer

  alias Example.Core.Ocsf
  alias Turnstile.Access
  alias Turnstile.Change
  alias Turnstile.Port

  @schema NimbleOptions.new!(
            name: [type: :any, doc: "A registered name, or none."],
            attach: [type: :boolean, default: false, doc: "Attach to the library's three events."]
          )

  @doc "Start the consumer. Options: #{NimbleOptions.docs(@schema)}"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    opts = NimbleOptions.validate!(opts, @schema)

    case opts[:name] do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "The OCSF schema version its records are mapped against."
  @spec schema_version() :: String.t()
  defdelegate schema_version, to: Ocsf, as: :version

  @doc "Every record it holds, oldest first."
  @spec records(GenServer.server()) :: [map()]
  def records(siem), do: GenServer.call(siem, :records)

  @doc "The records of one operation, oldest first."
  @spec records(GenServer.server(), String.t()) :: [map()]
  def records(siem, operation_id) when is_binary(operation_id) do
    siem
    |> records()
    |> Enum.filter(&(&1.metadata.correlation_uid == operation_id))
  end

  @doc false
  @spec handle_event([atom()], map(), map(), GenServer.server()) :: :ok
  def handle_event([:turnstile, :change], _measurements, payload, siem) do
    record(siem, Ocsf.change(payload))
  end

  def handle_event([:turnstile, :access], _measurements, payload, siem) do
    record(siem, Ocsf.access(payload))
  end

  def handle_event([:turnstile, :decision], _measurements, %{verdict: nil}, _siem), do: :ok

  def handle_event([:turnstile, :decision], %{duration: duration}, metadata, siem) do
    record(siem, Ocsf.decision(metadata, duration))
  end

  @impl GenServer
  def init(opts) do
    if opts[:attach] do
      Process.flag(:trap_exit, true)
      :ok = :telemetry.attach_many(handler_id(), events(), &__MODULE__.handle_event/4, self())
    end

    {:ok, %{records: [], attached: opts[:attach]}}
  end

  @impl GenServer
  def handle_cast({:record, record}, state), do: {:noreply, %{state | records: [record | state.records]}}

  @impl GenServer
  def handle_call(:records, _from, state), do: {:reply, Enum.reverse(state.records), state}

  @impl GenServer
  def terminate(_reason, %{attached: true}), do: :telemetry.detach(handler_id())
  def terminate(_reason, _state), do: :ok

  # The decision event, the change event, and the access event.
  defp events, do: [Port.event(), Change.event(), Access.event()]

  # Hold one record: what the handler does with what it mapped.
  defp record(siem, record) when is_map(record), do: GenServer.cast(siem, {:record, record})

  defp handler_id, do: {__MODULE__, self()}
end
