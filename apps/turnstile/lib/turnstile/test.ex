defmodule Turnstile.Test do
  @moduledoc """
  Helpers every test tier and a third party's adapter suite share: the
  configuration override, the clock a test sets, settling the configured
  adapter's projection, and polling with a deadline in place of sleeping.
  Shipped in core so Tier 1 can run outside this repository.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Ecto, NimbleOptions], exports: [Clock, Cluster, Fake]

  alias Turnstile.Change
  alias Turnstile.Config

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
  Bring the configured adapter's own state into step with the tables and
  answer `:ok`. An adapter that keeps no state of its own has nothing to
  settle, and the answer is `:none`, so a shared scenario can settle after
  writing facts without naming an adapter. Raises what settling failed with,
  since a scenario that cannot settle cannot ask its question.
  """
  @spec settle() :: :ok | :none
  def settle do
    {:ok, config} = Config.resolve()
    {adapter, _options} = Config.adapter(config)

    case settled(adapter) do
      :ok -> :ok
      :none -> :none
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
  The change events the calling process published while `fun` ran, in
  order, with what `fun` returned. Only this process's changes count, so
  async tests never see one another's.
  """
  @spec changes((-> term())) :: {term(), [map()]}
  def changes(fun) when is_function(fun, 0) do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, Change.event(), &__MODULE__.__change__/4, %{pid: self(), id: id})

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

  @doc false
  @spec __change__([atom()], map(), map(), map()) :: :ok
  def __change__(_event, _measurements, payload, %{pid: pid, id: id}) do
    if self() == pid, do: send(pid, {id, payload})
    :ok
  end

  defp settled(adapter) do
    if Code.ensure_loaded?(adapter) and function_exported?(adapter, :settle, 0) do
      adapter.settle()
    else
      :none
    end
  end

  defp collect(id, collected) do
    receive do
      {^id, one} -> collect(id, [one | collected])
    after
      0 -> Enum.reverse(collected)
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
