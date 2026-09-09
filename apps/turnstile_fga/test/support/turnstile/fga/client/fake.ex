defmodule Turnstile.Fga.Client.Fake do
  @moduledoc """
  The client behaviour on an `Agent`: stores, models, and tuples in one
  process, so a suite drives the projector and the adapter without a server.
  A test starts one of its own and passes the agent as the endpoint.

  What it copies from the server is what a caller can get wrong. A write is
  atomic per call: a call that carries a duplicate write, a delete of a tuple
  the store does not hold, a tuple key on both of its sides, or more changes
  than one call may carry changes nothing at all. A batch of more checks
  than one call may carry is refused the same way. Deletes and writes are
  matched by the tuple key alone, so a tuple written again with another
  condition is a duplicate.

  What it does not copy is the model. `check/3`, `list_objects/3`, and
  `expand/3` answer from the tuples the store holds directly, with no
  relation composed and no condition evaluated, in the types the real client
  answers in. Deciding is what a server does, and the cases that need one run
  against a server.

  `fail_after/2` makes the next writes fail once a number of them have been
  acknowledged, which is how a test interrupts a drain part way.
  """

  @behaviour Turnstile.Fga.Client

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Fga]
  use Agent

  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.BatchCheck
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.Expand
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Tree
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.TupleKey

  @doc "Start a fake with no store in it."
  @spec start_link(keyword()) :: Agent.on_start()
  def start_link(options \\ []) when is_list(options) do
    Agent.start_link(fn -> %{stores: %{}, next: 0, calls: [], fail_after: nil} end, options)
  end

  @doc "Every call made, in the order they were made, as the operation and its request."
  @spec calls(pid()) :: [{atom(), term()}]
  def calls(agent), do: Agent.get(agent, &Enum.reverse(&1.calls))

  @doc "The write calls made, in order."
  @spec writes(pid()) :: [Write.t()]
  def writes(agent) do
    for {:write, %Write{} = request} <- calls(agent), do: request
  end

  @doc "The tuples the store holds, sorted by key."
  @spec tuples(pid(), Client.store()) :: [TupleKey.t()]
  def tuples(agent, store) do
    Agent.get(agent, fn state ->
      held = Map.get(state.stores, store, %{tuples: %{}})

      Enum.sort_by(Map.values(held.tuples), &TupleKey.key/1)
    end)
  end

  @doc "Fail every write once this many more have been acknowledged; `nil` fails none."
  @spec fail_after(pid(), non_neg_integer() | nil) :: :ok
  def fail_after(agent, count) when is_nil(count) or (is_integer(count) and count >= 0) do
    Agent.update(agent, &%{&1 | fail_after: count})
  end

  @impl Client
  def create_store(agent, name) when is_binary(name) do
    Agent.get_and_update(agent, fn state ->
      store = "store-#{state.next + 1}"
      stores = Map.put(state.stores, store, %{name: name, models: [], tuples: %{}})

      {{:ok, store}, %{record(state, :create_store, name) | stores: stores, next: state.next + 1}}
    end)
  end

  @impl Client
  def write_model(agent, store, model) when is_binary(store) and is_map(model) do
    Agent.get_and_update(agent, fn state -> published(record(state, :write_model, model), store, model) end)
  end

  @impl Client
  def check(agent, store, %Check{} = request) do
    answer(agent, :check, store, request, fn tuples ->
      {:ok, Map.has_key?(tuples, TupleKey.key(request.tuple_key))}
    end)
  end

  @impl Client
  def batch_check(agent, store, %BatchCheck{} = request) do
    with :ok <- counted(request) do
      answer(agent, :batch_check, store, request, fn tuples ->
        {:ok, Map.new(request.checks, fn {id, key} -> {id, Map.has_key?(tuples, TupleKey.key(key))} end)}
      end)
    end
  end

  @impl Client
  def list_objects(agent, store, %ListObjects{} = request) do
    answer(agent, :list_objects, store, request, fn tuples -> {:ok, objects(tuples, request)} end)
  end

  @impl Client
  def expand(agent, store, %Expand{} = request) do
    answer(agent, :expand, store, request, fn tuples -> {:ok, tree(tuples, request)} end)
  end

  @impl Client
  def read(agent, store, %Read{} = request) do
    answer(agent, :read, store, request, fn tuples -> {:ok, page(tuples, request)} end)
  end

  @impl Client
  def write(agent, store, %Write{} = request) do
    Agent.get_and_update(agent, fn state -> written(record(state, :write, request), store, request) end)
  end

  defp record(state, operation, request), do: %{state | calls: [{operation, request} | state.calls]}

  defp answer(agent, operation, store, request, fun) do
    Agent.get_and_update(agent, fn state ->
      recorded = record(state, operation, request)

      case fetch(recorded, operation, store) do
        {:ok, held} -> {fun.(held.tuples), recorded}
        {:error, error} -> {{:error, error}, recorded}
      end
    end)
  end

  defp fetch(state, operation, store) do
    case Map.fetch(state.stores, store) do
      {:ok, held} -> {:ok, held}
      :error -> {:error, Client.error(operation, "the store #{store} is not there")}
    end
  end

  defp published(state, store, model) do
    case fetch(state, :write_model, store) do
      {:ok, held} -> {{:ok, "model-#{length(held.models) + 1}"}, hold(state, store, held, model)}
      {:error, error} -> {{:error, error}, state}
    end
  end

  # The models a store holds, newest first, so the id a publication answers
  # with counts them.
  defp hold(state, store, held, model) do
    put_in(state.stores[store], %{held | models: [model | held.models]})
  end

  # Every refusal is decided before anything is put back, so a call that one
  # of its changes fails leaves the store as it was.
  defp written(state, store, %Write{} = request) do
    case applied(state, store, request) do
      {:ok, tuples} -> {{:ok, length(request.deletes) + length(request.writes)}, kept(state, store, tuples)}
      {:error, error} -> {{:error, error}, state}
    end
  end

  defp applied(state, store, %Write{} = request) do
    with :ok <- allowed(state),
         {:ok, held} <- fetch(state, :write, store),
         :ok <- limited(request),
         :ok <- disjoint(request),
         {:ok, deleted} <- Enum.reduce_while(request.deletes, {:ok, held.tuples}, &delete_one/2) do
      Enum.reduce_while(request.writes, {:ok, deleted}, &write_one/2)
    end
  end

  defp kept(state, store, tuples) do
    held = Map.fetch!(state.stores, store)
    updated = put_in(state.stores[store], %{held | tuples: tuples})

    countdown(updated)
  end

  defp countdown(%{fail_after: nil} = state), do: state
  defp countdown(%{fail_after: count} = state), do: %{state | fail_after: count - 1}

  defp allowed(%{fail_after: 0}), do: {:error, Client.error(:write, "the fake was asked to fail this write")}
  defp allowed(%{}), do: :ok

  defp counted(%BatchCheck{checks: checks}) do
    if length(checks) > Client.max_checks_per_batch() do
      {:error, Client.error(:batch_check, "the call carries #{length(checks)} checks, above the limit of one call")}
    else
      :ok
    end
  end

  defp limited(%Write{} = request) do
    changes = length(request.deletes) + length(request.writes)

    if changes > Client.max_tuples_per_write() do
      {:error, Client.error(:write, "the call carries #{changes} changes, above the limit of one call")}
    else
      :ok
    end
  end

  defp disjoint(%Write{} = request) do
    keys = MapSet.new(request.deletes, &TupleKey.key/1)

    case Enum.find(request.writes, &MapSet.member?(keys, TupleKey.key(&1))) do
      nil -> :ok
      tuple -> {:error, Client.error(:write, "the call deletes and writes #{TupleKey.describe(tuple)}")}
    end
  end

  defp delete_one(tuple, {:ok, tuples}) do
    case Map.pop(tuples, TupleKey.key(tuple)) do
      {nil, _rest} -> {:halt, {:error, missing(tuple)}}
      {_held, rest} -> {:cont, {:ok, rest}}
    end
  end

  defp write_one(tuple, {:ok, tuples}) do
    key = TupleKey.key(tuple)

    if Map.has_key?(tuples, key) do
      {:halt, {:error, duplicate(tuple)}}
    else
      {:cont, {:ok, Map.put(tuples, key, tuple)}}
    end
  end

  defp missing(tuple) do
    Client.error(:write, "the call deletes #{TupleKey.describe(tuple)}, which the store does not hold")
  end

  defp duplicate(tuple) do
    Client.error(:write, "the call writes #{TupleKey.describe(tuple)}, which the store holds already")
  end

  defp objects(tuples, %ListObjects{} = request) do
    matching =
      for tuple <- Map.values(tuples),
          tuple.user == request.user,
          tuple.relation == request.relation,
          TupleKey.object_type(tuple) == request.type,
          do: tuple.object

    matching
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp tree(tuples, %Expand{} = request) do
    users =
      for tuple <- Map.values(tuples),
          tuple.relation == request.relation,
          tuple.object == request.object,
          do: tuple.user

    %Tree{object: request.object, relation: request.relation, users: Enum.sort(users), children: []}
  end

  defp page(tuples, %Read{} = request) do
    matching =
      tuples
      |> Map.values()
      |> Enum.filter(&matches?(&1, request))
      |> Enum.sort_by(&TupleKey.key/1)

    offset = offset(request.continuation)
    taken = Enum.slice(matching, offset, request.limit)

    %Page{tuples: taken, continuation: continuation(offset + length(taken), length(matching))}
  end

  defp continuation(read, held) when read < held, do: to_string(read)
  defp continuation(_read, _held), do: nil

  defp offset(nil), do: 0
  defp offset(continuation), do: String.to_integer(continuation)

  defp matches?(tuple, %Read{} = request) do
    TupleKey.object_type(tuple) == request.object_type and
      same?(tuple.object, object(request)) and
      same?(tuple.relation, request.relation) and
      same?(tuple.user, request.user)
  end

  defp object(%Read{object_id: nil}), do: nil
  defp object(%Read{} = request), do: "#{request.object_type}:#{request.object_id}"

  defp same?(_value, nil), do: true
  defp same?(value, value), do: true
  defp same?(_value, _asked), do: false
end
