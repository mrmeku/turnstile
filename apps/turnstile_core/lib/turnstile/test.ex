defmodule Turnstile.Test do
  @moduledoc """
  Helpers every test tier and a third party's adapter suite share: the
  configuration override, and polling with a deadline in place of sleeping.
  Shipped in core so Tier 1 can run outside this repository.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Ecto], exports: [Cluster]

  alias Turnstile.Config

  @default_timeout 5_000
  @interval 10

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
  Calls `fun` until it returns a truthy value or `timeout` milliseconds pass.
  Returns the truthy value. Raises with the last value on timeout. This is
  the one place the suite sleeps.
  """
  @spec poll((-> term()), pos_integer()) :: term()
  def poll(fun, timeout \\ @default_timeout) when is_function(fun, 0) do
    deadline = System.monotonic_time(:millisecond) + timeout
    poll_until(fun, deadline, nil)
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
