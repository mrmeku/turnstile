defmodule Turnstile.Test do
  @moduledoc """
  Helpers every test tier and a third party's adapter suite share: the
  configuration override, settling the configured adapter's projection, and
  polling with a deadline in place of sleeping. Shipped in core so Tier 1 can
  run outside this repository.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Ecto], exports: [Cerbos, Cluster, Fga]

  alias Turnstile.Config
  alias Turnstile.Projection.Drain

  @default_timeout 5_000
  @interval 10
  @control ~r/^\s*(begin|commit|rollback|savepoint|release)\b/i

  @doc """
  Override configuration fields for the rest of the calling process.
  `Turnstile.Config.resolve/0` reads the override from the caller and from
  its `$callers` chain, over the boot struct when one exists.
  """
  @spec with_config(keyword()) :: :ok
  def with_config(overrides) when is_list(overrides) do
    current = Process.get(Config.override_key(), [])
    Process.put(Config.override_key(), Keyword.merge(current, overrides))
    :ok
  end

  @doc "Override configuration fields around a function, restoring the previous override after it."
  @spec with_config(keyword(), (-> result)) :: result when result: term()
  def with_config(overrides, fun) when is_list(overrides) and is_function(fun, 0) do
    previous = Process.get(Config.override_key(), [])
    :ok = with_config(overrides)

    try do
      fun.()
    after
      Process.put(Config.override_key(), previous)
    end
  end

  @doc """
  Drain the configured adapter's projection until it has applied the ledger's
  head, and answer `:ok`. An adapter that projects nothing has nothing to
  drain, and the answer is `:none`, so a shared scenario can settle after
  writing facts without naming an adapter. Raises what the projection or the
  ledger failed with, since a scenario that cannot settle cannot ask its
  question.
  """
  @spec settle() :: :ok | :none
  def settle do
    {:ok, config} = Config.resolve()
    {adapter, _options} = Config.adapter(config)

    case projection(adapter) do
      :none -> :none
      {:ok, {module, state}} -> drained(module, state, head(config))
      {:error, error} -> raise error
    end
  end

  @doc """
  The SQL statements the calling process ran on `repo` while `fun` ran,
  read from the repo's `[..., :query]` telemetry, transaction control
  filtered out, in order. Only this process's queries count, so async
  tests never see one another's.
  """
  @spec queries(module(), (-> term())) :: {term(), [String.t()]}
  def queries(repo, fun) when is_atom(repo) and is_function(fun, 0) do
    event = List.insert_at(repo.config()[:telemetry_prefix], -1, :query)
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, event, &__MODULE__.__query__/4, %{pid: self(), id: id})

    try do
      result = fun.()
      {result, collect(id, [])}
    after
      :telemetry.detach(id)
    end
  end

  @doc """
  Calls `fun` until it returns a truthy value or `timeout` milliseconds pass.
  Returns the truthy value. Raises with the last value on timeout. This is
  the one place the suite sleeps.
  """
  @spec poll((-> term()), pos_integer()) :: term()
  def poll(fun, timeout \\ @default_timeout) when is_function(fun, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_until(fun, deadline, nil)
  end

  @doc "The poll interval, the floor of any measurement `poll/2` takes, in milliseconds."
  @spec poll_interval() :: pos_integer()
  def poll_interval, do: @interval

  @doc false
  @spec __query__([atom()], map(), map(), map()) :: :ok
  def __query__(_event, _measurements, %{query: query}, %{pid: pid, id: id}) do
    if self() == pid and not Regex.match?(@control, query), do: send(pid, {id, query})
    :ok
  end

  defp projection(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :projection, 0) do
      adapter.projection()
    else
      :none
    end
  end

  defp head(%Config{ledger: :none}), do: 0

  defp head(%Config{ledger: {module, options}}) do
    {:ok, head} = module.head(options)
    head
  end

  # One drain covers every event the reader answers with, so the loop is for
  # events appended while it ran; a drain that applied nothing has caught up
  # even where the head is ahead of the last event the reader can see.
  defp drained(module, state, head) do
    case module.drain_once(state) do
      {:ok, %Drain{to: to, applied: applied}} when to >= head or applied == 0 -> :ok
      {:ok, %Drain{}} -> drained(module, state, head)
      {:error, error} -> raise error
    end
  end

  defp collect(id, queries) do
    receive do
      {^id, query} -> collect(id, [query | queries])
    after
      0 -> Enum.reverse(queries)
    end
  end

  defp poll_until(fun, deadline, last) do
    case fun.() do
      falsy when falsy in [nil, false] ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "poll timed out; last value: #{inspect(last)}"
        else
          Process.sleep(@interval)
          poll_until(fun, deadline, falsy)
        end

      value ->
        value
    end
  end
end
