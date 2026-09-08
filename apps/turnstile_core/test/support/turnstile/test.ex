defmodule Turnstile.Test do
  @moduledoc "Helpers shared by every test tier. No sleeps: waiting is polling with a deadline."

  @default_timeout 5_000
  @interval 10

  @doc """
  Calls `fun` until it returns a truthy value or `timeout` milliseconds pass.
  Returns the truthy value. Raises with the last value on timeout.
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
