defmodule Turnstile.Dev do
  @moduledoc """
  What this repository's suites need and no adopter does. The modules under
  this name raise the ephemeral cluster, set up the sandbox, dump a schema,
  and start the engines the suites ask; this one holds the waiting they
  share. Nothing here is a dependency of a published package outside its
  test environment.
  """

  use Boundary, top_level?: true, deps: []

  @default_timeout 5_000
  @interval 10

  @doc """
  Calls `fun` until it returns a truthy value or `timeout` milliseconds pass.
  Returns the truthy value. Raises with the last value on timeout. This is
  the one place this package sleeps.
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
