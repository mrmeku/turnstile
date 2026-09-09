defmodule Example.Audit do
  @moduledoc """
  The example's audit store: every decision event the port emits and every
  override read, as records chained by hash, so a rewritten record breaks
  every hash after it (AU-9). The library does not own the audit store;
  this is what an application does with the events, and the shape the
  scenarios assert.
  """

  alias Example.Audit.Store

  @doc "The records of an operation, from the store, oldest first."
  @spec records(GenServer.server(), String.t()) :: [Example.Audit.Record.t()]
  defdelegate records(store, operation_id), to: Store

  @doc "Verify the store's chain."
  @spec verify(GenServer.server()) :: :ok | {:error, [non_neg_integer()]}
  defdelegate verify(store), to: Store
end

defmodule Example.Audit.Record do
  @moduledoc "One chained record: its index, kind, time, operation id, payload, the previous hash, and its own."

  @enforce_keys [:index, :kind, :at, :operation_id, :payload, :previous, :hash]
  defstruct @enforce_keys

  @type kind :: :decision | :override

  @type t :: %__MODULE__{
          index: non_neg_integer(),
          kind: kind(),
          at: DateTime.t(),
          operation_id: String.t() | nil,
          payload: map(),
          previous: String.t(),
          hash: String.t()
        }

  @doc "The hash of a record's content over the previous hash; what `verify` recomputes."
  @spec digest(t()) :: String.t()
  def digest(%__MODULE__{} = record) do
    content = {record.index, record.kind, record.at, record.operation_id, record.payload}
    binary = :erlang.term_to_binary(content, [:deterministic])
    Base.encode16(:crypto.hash(:sha256, record.previous <> binary), case: :lower)
  end
end

defmodule Example.Audit.Chain do
  @moduledoc """
  The chain as a value: append hashes the record over the previous hash,
  verify recomputes every hash from the genesis and names every index that
  no longer matches. Rewriting a record is a function here, so the tamper
  case is a plain computation.
  """

  alias Example.Audit.Record

  @genesis "genesis"

  defstruct records: [], head: @genesis

  @type t :: %__MODULE__{records: [Record.t()], head: String.t()}

  @doc "An empty chain."
  @spec new() :: t()
  def new, do: %__MODULE__{}

  @doc "Append a record of a kind with a payload, at a time."
  @spec append(t(), Record.kind(), String.t() | nil, map(), DateTime.t()) :: t()
  def append(%__MODULE__{records: records, head: head} = chain, kind, operation_id, payload, %DateTime{} = at)
      when kind in [:decision, :override] and is_map(payload) do
    record = %Record{
      index: length(records),
      kind: kind,
      at: at,
      operation_id: operation_id,
      payload: payload,
      previous: head,
      hash: ""
    }

    record = %{record | hash: Record.digest(record)}
    %{chain | records: [record | records], head: record.hash}
  end

  @doc "The records, oldest first."
  @spec records(t()) :: [Record.t()]
  def records(%__MODULE__{records: records}), do: Enum.reverse(records)

  @doc "Every index whose hash does not follow from the genesis and the records before it; `:ok` when none."
  @spec verify(t()) :: :ok | {:error, [non_neg_integer()]}
  def verify(%__MODULE__{} = chain) do
    {broken, _head} =
      Enum.reduce(records(chain), {[], @genesis}, fn %Record{} = record, {broken, previous} ->
        expected = Record.digest(%{record | previous: previous})
        broken = if record.hash == expected and record.previous == previous, do: broken, else: [record.index | broken]
        {broken, expected}
      end)

    case broken do
      [] -> :ok
      indexes -> {:error, Enum.reverse(indexes)}
    end
  end

  @doc "The chain with one record's payload replaced and nothing rehashed: what tampering looks like."
  @spec rewrite(t(), non_neg_integer(), (map() -> map())) :: t()
  def rewrite(%__MODULE__{records: records} = chain, index, fun) when is_integer(index) and is_function(fun, 1) do
    rewritten =
      Enum.map(records, fn
        %Record{index: ^index} = record -> %{record | payload: fun.(record.payload)}
        record -> record
      end)

    %{chain | records: rewritten}
  end
end

defmodule Example.Audit.Store do
  @moduledoc """
  A process holding a chain and, when told to, attached to the port's
  `:stop` events and the override event. Records arrive as casts and are
  read as calls, so a caller that emitted an event reads its own records
  afterwards. The thin application starts one at boot; a test starts its
  own, unattached, and feeds it records.
  """

  use GenServer

  alias Example.Audit.Chain
  alias Example.Audit.Record
  alias Example.Documents

  @schema NimbleOptions.new!(
            name: [type: :any, doc: "A registered name, or none."],
            attach: [type: :boolean, default: false, doc: "Attach to the port's events and the override event."]
          )

  @doc "Start the store. Options: #{NimbleOptions.docs(@schema)}"
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts \\ []) when is_list(opts) do
    opts = NimbleOptions.validate!(opts, @schema)

    case opts[:name] do
      nil -> GenServer.start_link(__MODULE__, opts)
      name -> GenServer.start_link(__MODULE__, opts, name: name)
    end
  end

  @doc "Record one payload of a kind; what the telemetry handler does."
  @spec record(GenServer.server(), Record.kind(), String.t() | nil, map()) :: :ok
  def record(store, kind, operation_id, payload) when kind in [:decision, :override] and is_map(payload) do
    GenServer.cast(store, {:record, kind, operation_id, payload, DateTime.utc_now()})
  end

  @doc "The records of an operation, oldest first."
  @spec records(GenServer.server(), String.t()) :: [Record.t()]
  def records(store, operation_id) when is_binary(operation_id) do
    store
    |> chain()
    |> Chain.records()
    |> Enum.filter(&(&1.operation_id == operation_id))
  end

  @doc "The whole chain."
  @spec chain(GenServer.server()) :: Chain.t()
  def chain(store), do: GenServer.call(store, :chain)

  @doc "Verify the chain."
  @spec verify(GenServer.server()) :: :ok | {:error, [non_neg_integer()]}
  def verify(store) do
    store
    |> chain()
    |> Chain.verify()
  end

  @doc "The events the store attaches to: the port's `:stop` spans and the override event."
  @spec events() :: [[atom()]]
  def events do
    [Documents.override_event() | Enum.filter(Turnstile.Port.events(), &(List.last(&1) == :stop))]
  end

  @doc false
  @spec handle_event([atom()], map(), map(), GenServer.server()) :: :ok
  def handle_event([:turnstile, _kind, :stop], _measurements, %{decision: decision} = metadata, store)
      when is_map(decision) do
    record(store, :decision, metadata[:operation_id], decision)
  end

  def handle_event([:turnstile, _kind, :stop], _measurements, _metadata, _store), do: :ok

  def handle_event([:example, :override, :read], _measurements, %{report: report, subject: subject}, store) do
    payload = %{subject: subject, document_id: report.document_id, office_id: report.office_id}
    record(store, :override, report.operation_id, payload)
  end

  @impl GenServer
  def init(opts) do
    if opts[:attach] do
      Process.flag(:trap_exit, true)
      :ok = :telemetry.attach_many(handler_id(), events(), &__MODULE__.handle_event/4, self())
    end

    {:ok, %{chain: Chain.new(), attached: opts[:attach]}}
  end

  @impl GenServer
  def handle_cast({:record, kind, operation_id, payload, at}, state) do
    {:noreply, %{state | chain: Chain.append(state.chain, kind, operation_id, payload, at)}}
  end

  @impl GenServer
  def handle_call(:chain, _from, state), do: {:reply, state.chain, state}

  @impl GenServer
  def terminate(_reason, %{attached: true}), do: :telemetry.detach(handler_id())
  def terminate(_reason, _state), do: :ok

  defp handler_id, do: {__MODULE__, self()}
end
