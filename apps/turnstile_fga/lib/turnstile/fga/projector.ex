defmodule Turnstile.Fga.Projector do
  @moduledoc """
  `Turnstile.Projection` over a tuple mapping: the ledger's fact events
  become tuples in a store, and the store is a copy that this process keeps
  current rather than the application's own tables.

  A drain reads every event above the checkpoint, folds the whole ledger,
  and asks the mapping which objects those events can have changed. Per
  object it reads what the store holds, computes the difference against what
  the fold requires, and writes that difference alone. Nothing about an event
  is translated into a write directly, which is why a drain that runs twice
  over the same events writes nothing the second time.

  The checkpoint advances after each acknowledged write, to the position of
  the last event every object of which is done. An object whose difference
  asks for one tuple to be deleted and written again takes two calls, since
  one call refuses a tuple key on both of its sides, and the state between
  those two calls is neither the old one nor the new one: the checkpoint
  stays below that event until the second call is acknowledged. A drain that
  fails part way therefore leaves a checkpoint that is exact, and the next
  drain reads from it and converges.

  A store no checkpoint row names stands at zero, which is where genesis
  sits, so the first drain over a ledger whose genesis wrote every current
  fact reads that event too. A drain that finds no difference still advances
  the checkpoint at its end, because events the store already satisfies are
  covered by what is there.

  The drain interval belongs to the process a thin application starts. What
  is here is driven: a test calls `drain_once/1` and `reconcile/1` itself.
  """

  @behaviour Turnstile.Projection

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Checkpoint
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Ledger.Fold
  alias Turnstile.Ledger.Reader
  alias Turnstile.Projection.Drain
  alias Turnstile.Projection.Drift

  @schema NimbleOptions.new!(
            client: [
              type: :atom,
              required: true,
              doc: "The `Turnstile.Fga.Client` implementation, the fake in tests."
            ],
            endpoint: [
              type: :any,
              required: true,
              doc: "What the client talks to: the address of a server, or the process a fake runs on."
            ],
            store: [type: :string, required: true, doc: "The store this projector drains into."],
            store_name: [
              type: :string,
              default: "turnstile",
              doc: "The name `rebuild/1` gives the store it creates."
            ],
            model: [
              type: {:map, :string, :any},
              required: true,
              doc: "The model `rebuild/1` publishes into the store it creates, as the server takes it."
            ],
            mapping: [type: :atom, required: true, doc: "The `Turnstile.Fga.TupleMapping` implementation."],
            ledger: [
              type: {:tuple, [:atom, :keyword_list]},
              required: true,
              doc: "The ledger as `{module, options}`, read through `Turnstile.Ledger.Reader`."
            ],
            repo: [type: :atom, required: true, doc: "The repo holding the checkpoint table."],
            batch: [
              type: :pos_integer,
              doc:
                "How many changes one write carries, and how many tuples one read page holds. " <>
                  "Defaults to the number of changes one call may carry."
            ]
          )

  @enforce_keys [:client, :endpoint, :store, :store_name, :model, :mapping, :ledger, :repo, :batch]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          client: module(),
          endpoint: Client.endpoint(),
          store: Client.store(),
          store_name: String.t(),
          model: map(),
          mapping: module(),
          ledger: {module(), keyword()},
          repo: module(),
          batch: pos_integer()
        }

  @doc "The schema of the projector's configuration. Fields: #{NimbleOptions.docs(@schema)}"
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @schema

  @doc "A projector from its configuration."
  @spec new(keyword()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def new(options) when is_list(options) do
    # The default is read here rather than in the schema, so the limit of one
    # call stays the client's to state and this module compiles beside it.
    filled = Keyword.put_new(options, :batch, Client.max_tuples_per_write())

    case NimbleOptions.validate(filled, @schema) do
      {:ok, valid} -> {:ok, struct!(__MODULE__, valid)}
      {:error, error} -> {:error, %Error.Invalid{what: :projector, detail: Exception.message(error)}}
    end
  end

  @doc """
  The projector the configuration and the binding together describe: the
  adapter entry's endpoint, store, and client, the binding's repo, mapping,
  and compiled model, and the ledger the configuration names. This is what
  the process a thin application starts drains with, and what a test that
  drains by hand resolves for itself.
  """
  @spec resolve() :: {:ok, t()} | {:error, Error.Invalid.t() | Error.Unsupported.t()}
  def resolve do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve(),
         {:ok, ledger} <- ledger(config),
         {:ok, options} <- entry(config),
         {:ok, model} <- Binding.compiled(binding) do
      new(
        client: Keyword.get(options, :client, Client.Http),
        endpoint: Keyword.fetch!(options, :endpoint),
        store: Keyword.fetch!(options, :store_id),
        model: model,
        mapping: binding.mapping,
        ledger: ledger,
        repo: binding.repo
      )
    end
  end

  @impl Turnstile.Projection
  def checkpoint(%__MODULE__{} = projector), do: {:ok, Checkpoint.position(projector.repo, projector.store)}

  @impl Turnstile.Projection
  def drain_once(%__MODULE__{} = projector) do
    from = Checkpoint.position(projector.repo, projector.store)

    with {:ok, events} <- Reader.all(projector.ledger) do
      drain(projector, Fold.fold(events), above(events, from), from)
    end
  end

  @impl Turnstile.Projection
  def rebuild(%__MODULE__{} = projector) do
    with {:ok, store} <- projector.client.create_store(projector.endpoint, projector.store_name),
         {:ok, _model} <- projector.client.write_model(projector.endpoint, store, projector.model),
         {:ok, %Drain{}} <- drain_once(%{projector | store: store}) do
      {:ok, store}
    end
  end

  @impl Turnstile.Projection
  def reconcile(%__MODULE__{} = projector) do
    with {:ok, events} <- Reader.all(projector.ledger),
         {:ok, present} <- stored(projector) do
      fold = Fold.fold(events)
      {:ok, drift(required(projector, fold, events), present, fold.position)}
    end
  end

  defp entry(%Config{} = config) do
    case Config.adapter(config) do
      {Turnstile.Fga, options} -> {:ok, options}
      {other, _options} -> {:error, invalid("#{inspect(other)} is the configured adapter, so it drains nothing here")}
    end
  end

  defp ledger(%Config{ledger: :none}) do
    {:error,
     %Error.Unsupported{
       adapter: Turnstile.Fga,
       feature: :ledger_mode_none,
       note: "a projection has nothing to drain without a ledger"
     }}
  end

  defp ledger(%Config{ledger: {module, options}}), do: {:ok, {module, options}}

  defp invalid(detail), do: %Error.Invalid{what: :projector, detail: detail}

  # Genesis sits at position zero and a ledger read is exclusive of the
  # position it starts from, so a checkpoint of zero reads everything.
  defp above(events, 0), do: events
  defp above(events, from), do: Enum.filter(events, &(&1.position > from))

  defp drain(projector, fold, pending, from) do
    touched = for event <- pending, do: {event.position, MapSet.new(projector.mapping.touched(fold, event))}
    step = &object_step(projector, fold, touched, from, {&1, &2})

    case Enum.reduce_while(objects(touched), MapSet.new(), step) do
      {:error, error} -> {:error, error}
      %MapSet{} -> finish(projector, pending, from)
    end
  end

  # Objects in the order the events first touch them, so a drain that fails
  # part way has covered a prefix of the events rather than a scattering.
  defp objects(touched) do
    touched
    |> Enum.flat_map(fn {_position, objects} -> Enum.sort(objects) end)
    |> Enum.uniq()
  end

  defp object_step(projector, fold, touched, from, {object, done}) do
    interim = covered(touched, done, from)
    complete = MapSet.put(done, object)

    case apply_object(projector, fold, object, {interim, covered(touched, complete, from)}) do
      :ok -> {:cont, complete}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp apply_object(projector, fold, object, positions) do
    with {:ok, present} <- present(projector, object) do
      {deletes, writes} = difference(projector.mapping.tuples(fold, object), present)

      run_calls(projector, calls(deletes, writes, projector.batch), positions)
    end
  end

  defp finish(projector, pending, from) do
    to = last_position(pending, from)
    :ok = advance(projector, to)

    {:ok, %Drain{from: from, to: to, applied: length(pending)}}
  end

  defp last_position([], from), do: from
  defp last_position(pending, _from), do: List.last(pending).position

  # The last event every object of which is done. An event whose objects are
  # partly written is not covered, because the state it describes is not
  # there yet.
  defp covered(touched, done, from) do
    covered = Enum.take_while(touched, fn {_position, objects} -> MapSet.subset?(objects, done) end)

    case List.last(covered) do
      nil -> from
      {position, _objects} -> position
    end
  end

  defp run_calls(_projector, [], _positions), do: :ok

  defp run_calls(projector, [call | rest], {interim, final} = positions) do
    case projector.client.write(projector.endpoint, projector.store, call) do
      {:ok, _count} ->
        :ok = advance(projector, position_of(rest, interim, final))
        run_calls(projector, rest, positions)

      {:error, error} ->
        {:error, error}
    end
  end

  defp position_of([], _interim, final), do: final
  defp position_of([_next | _rest], interim, _final), do: interim

  defp advance(projector, position), do: Checkpoint.advance(projector.repo, projector.store, position)

  defp present(projector, object) do
    [type | id] = String.split(object, ":", parts: 2)

    read_pages(projector, %Read{object_type: type, object_id: List.first(id), limit: projector.batch}, [])
  end

  defp read_pages(projector, %Read{} = request, done) do
    case projector.client.read(projector.endpoint, projector.store, request) do
      {:ok, %Page{continuation: nil} = page} -> {:ok, Enum.concat(Enum.reverse([page.tuples | done]))}
      {:ok, %Page{} = page} -> read_pages(projector, %{request | continuation: page.continuation}, [page.tuples | done])
      {:error, error} -> {:error, error}
    end
  end

  # A tuple is identified by its user, its relation, and its object, and a
  # condition is a value on it, so a tuple whose condition changed is the
  # same key with another value: a delete and a write of that key.
  defp difference(required, present) do
    wanted = by_key(required)
    have = by_key(present)

    deletes = for {key, tuple} <- have, Map.get(wanted, key) != tuple, do: tuple
    writes = for {key, tuple} <- wanted, Map.get(have, key) != tuple, do: tuple

    {sorted(deletes), sorted(writes)}
  end

  defp by_key(tuples), do: Map.new(tuples, &{TupleKey.key(&1), &1})

  defp sorted(tuples), do: Enum.sort_by(tuples, &TupleKey.key/1)

  # One call refuses a tuple key that appears in both its deletes and its
  # writes, so a key on both sides is written in a call of its own after the
  # deletion.
  defp calls(deletes, writes, batch) do
    keys = MapSet.new(deletes, &TupleKey.key/1)
    {rewritten, plain} = Enum.split_with(writes, &MapSet.member?(keys, TupleKey.key(&1)))

    packed(deletes, plain, batch) ++ packed([], rewritten, batch)
  end

  # Each call carries at most `batch` changes, its deletes and its writes
  # counted together, which is how the server counts them.
  defp packed([], [], _batch), do: []

  defp packed(deletes, writes, batch) do
    {call_deletes, rest_deletes} = Enum.split(deletes, batch)
    {call_writes, rest_writes} = Enum.split(writes, batch - length(call_deletes))

    [%Write{deletes: call_deletes, writes: call_writes} | packed(rest_deletes, rest_writes, batch)]
  end

  defp stored(projector) do
    step = fn type, {:ok, done} ->
      case read_pages(projector, %Read{object_type: type, limit: projector.batch}, []) do
        {:ok, tuples} -> {:cont, {:ok, done ++ tuples}}
        {:error, error} -> {:halt, {:error, error}}
      end
    end

    Enum.reduce_while(projector.mapping.object_types(), {:ok, []}, step)
  end

  defp required(projector, fold, events) do
    events
    |> Enum.flat_map(&projector.mapping.touched(fold, &1))
    |> Enum.uniq()
    |> Enum.flat_map(&projector.mapping.tuples(fold, &1))
  end

  defp drift(required, present, position) do
    wanted = MapSet.new(required)
    have = MapSet.new(present)

    %Drift{
      missing: sorted(MapSet.difference(wanted, have)),
      extra: sorted(MapSet.difference(have, wanted)),
      checked_to: position
    }
  end
end
