defmodule Turnstile.Adapter.Fake do
  @moduledoc """
  The adapter Tier 1 runs first and the seam's tests bind. Its rules are a
  table in an `Agent`, one per test, bound through the configuration override
  as `{Turnstile.Adapter.Fake, rules: pid}`: an entry allows one subject, or
  any, one operation, on one object, or any of a type, and nothing else is
  allowed. Without a table the fake answers with the `verdict` option,
  `:deny` unless said otherwise. It returns a value of the real type
  everywhere the real adapters do: `scope` returns a real `dynamic`,
  `explain` returns `Turnstile.Error.Unsupported`, and a table told to
  `fail/2` answers every call with `Turnstile.Error.Engine`, so the port's
  fail-closed path runs against it.
  """

  @behaviour Turnstile.Adapter

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject

  @version "fake"

  @schema NimbleOptions.new!(
            rules: [type: :pid, doc: "The rule table from `start_link/0`."],
            verdict: [
              type: {:in, [:allow, :deny]},
              default: :deny,
              doc: "The answer to everything when no rule table is bound."
            ]
          )

  @typedoc "A subject id or any subject; an operation; an object reference whose id may be any."
  @type entry :: {Turnstile.Id.t() | :any, atom(), {atom(), Turnstile.Id.t() | term() | :any}}

  @typep state :: %{entries: MapSet.t(entry()), failure: String.t() | nil}

  @doc "Starts an empty rule table, unnamed."
  @spec start_link() :: Agent.on_start()
  def start_link, do: Agent.start_link(fn -> %{entries: MapSet.new(), failure: nil} end)

  @doc "Allow `subject` (an id or `:any`) to perform `operation` on the object reference, whose id may be `:any`."
  @spec allow(pid(), Turnstile.Id.t() | :any, atom(), {atom(), term()}) :: :ok
  def allow(rules, subject, operation, {type, _id} = object)
      when is_pid(rules) and is_atom(operation) and is_atom(type) do
    Agent.update(rules, fn state -> %{state | entries: MapSet.put(state.entries, {subject, operation, object})} end)
  end

  @doc "Remove one entry."
  @spec revoke(pid(), Turnstile.Id.t() | :any, atom(), {atom(), term()}) :: :ok
  def revoke(rules, subject, operation, {type, _id} = object)
      when is_pid(rules) and is_atom(operation) and is_atom(type) do
    Agent.update(rules, fn state -> %{state | entries: MapSet.delete(state.entries, {subject, operation, object})} end)
  end

  @doc "Empty the table and clear any failure."
  @spec reset(pid()) :: :ok
  def reset(rules) when is_pid(rules), do: Agent.update(rules, fn _state -> %{entries: MapSet.new(), failure: nil} end)

  @doc "Make every call fail with the detail, or stop failing with `nil`."
  @spec fail(pid(), String.t() | nil) :: :ok
  def fail(rules, detail) when is_pid(rules) and (is_binary(detail) or is_nil(detail)) do
    Agent.update(rules, fn state -> %{state | failure: detail} end)
  end

  @doc "The entries, sorted."
  @spec entries(pid()) :: [entry()]
  def entries(rules) when is_pid(rules), do: Agent.get(rules, &Enum.sort(&1.entries))

  @impl Turnstile.Adapter
  def options_schema, do: @schema

  @impl Turnstile.Adapter
  def requires_ledger, do: false

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def authorize(%Subject{} = subject, operation, %Object{} = object, %Environment{}, options) when is_atom(operation) do
    with {:ok, state} <- state(options, :authorize) do
      {:ok, decide(state, subject, operation, object)}
    end
  end

  @impl Turnstile.Adapter
  def check(%Subject{} = subject, operation, %Object{} = object, %Environment{}, options) when is_atom(operation) do
    with {:ok, state} <- state(options, :check) do
      {:ok, decide(state, subject, operation, object)}
    end
  end

  @impl Turnstile.Adapter
  def batch(%Subject{} = subject, operation, objects, %Environment{}, options)
      when is_atom(operation) and is_list(objects) do
    with {:ok, state} <- state(options, :batch) do
      {:ok,
       Map.new(objects, fn %Object{} = object -> {Object.ref(object), decide(state, subject, operation, object)} end)}
    end
  end

  @impl Turnstile.Adapter
  def scope(%Subject{} = subject, operation, object_type, %Environment{}, options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, state} <- state(options, :scope) do
      {:ok, scoped(state, subject, operation, object_type)}
    end
  end

  @impl Turnstile.Adapter
  def explain(%Subject{}, operation, %Object{}, %Environment{}, _options) when is_atom(operation) do
    {:error, %Error.Unsupported{adapter: __MODULE__, feature: :explain, note: "the fake names no rule"}}
  end

  @doc "The answer the fake gives with no table bound; `Turnstile.Explanation` is never built from it."
  @spec answer(keyword()) :: Answer.t()
  def answer(options) when is_list(options), do: answer_for(Keyword.get(options, :verdict, :deny))

  defp answer_for(:allow) do
    %Answer{verdict: :allow, reason: Reason.allowed("fake"), policy_version: @version, applied_position: nil}
  end

  defp answer_for(:deny) do
    %Answer{verdict: :deny, reason: Reason.deny_by_default(), policy_version: @version, applied_position: nil}
  end

  # The table's state, the constant verdict as a table with one wildcard or
  # none, or the failure the table was told to give.
  @spec state(keyword(), atom()) :: {:ok, state() | :allow | :deny} | {:error, Error.Engine.t()}
  defp state(options, operation) do
    case Keyword.fetch(options, :rules) do
      {:ok, rules} -> read(Agent.get(rules, & &1), operation)
      :error -> {:ok, Keyword.get(options, :verdict, :deny)}
    end
  end

  defp read(%{failure: nil} = state, _operation), do: {:ok, state}

  defp read(%{failure: detail}, operation) do
    {:error, %Error.Engine{adapter: __MODULE__, operation: operation, detail: detail}}
  end

  defp decide(verdict, _subject, _operation, _object) when is_atom(verdict), do: answer_for(verdict)

  defp decide(%{entries: entries}, %Subject{id: id}, operation, %Object{type: type, id: object_id}) do
    candidates = [
      {id, operation, {type, object_id}},
      {:any, operation, {type, object_id}},
      {id, operation, {type, :any}},
      {:any, operation, {type, :any}}
    ]

    if Enum.any?(candidates, &MapSet.member?(entries, &1)), do: answer_for(:allow), else: answer_for(:deny)
  end

  defp scoped(:allow, _subject, _operation, _type), do: %Scope{rule: dynamic([_row], true), answer: answer_for(:allow)}
  defp scoped(:deny, _subject, _operation, _type), do: %Scope{rule: dynamic([_row], false), answer: answer_for(:deny)}

  defp scoped(%{entries: entries}, %Subject{id: id}, operation, type) do
    matching =
      Enum.filter(entries, fn
        {subject, ^operation, {^type, _object_id}} -> subject in [id, :any]
        _entry -> false
      end)

    ids = Enum.map(matching, fn {_subject, _operation, {_type, object_id}} -> object_id end)

    cond do
      :any in ids -> %Scope{rule: dynamic([_row], true), answer: answer_for(:allow)}
      ids == [] -> %Scope{rule: dynamic([_row], false), answer: answer_for(:deny)}
      true -> %Scope{rule: dynamic([row], row.id in ^ids), answer: answer_for(:allow)}
    end
  end
end
