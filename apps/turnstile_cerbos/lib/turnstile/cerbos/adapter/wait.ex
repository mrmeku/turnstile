defmodule Turnstile.Cerbos.Adapter.Wait do
  @moduledoc false
  # Waiting for a change to be in force. The sidecar reloads a policy
  # directory on its own schedule and announces nothing, so the only way to
  # learn that a change has arrived is to ask a question the change answers
  # differently, over and over, until it does.
  #
  # The clock is monotonic, so an adjustment of the system clock between two
  # asks cannot shorten or lengthen the deadline. The interval between asks
  # is the floor of any measurement taken this way, since a change in force
  # halfway through an interval is not seen until the interval is over, and
  # the measurement says so rather than claiming a number it cannot hold.

  @interval 10

  @doc "The milliseconds between asks, the floor of any measurement `until/2` takes."
  @spec interval() :: pos_integer()
  def interval, do: @interval

  @doc """
  Asks `fun` until it answers something other than `nil` or `false`, or
  until `timeout` milliseconds have passed. Comes back with that answer, or
  raises with the last one.
  """
  @spec until((-> term()), pos_integer()) :: term()
  def until(fun, timeout) when is_function(fun, 0) and is_integer(timeout) and timeout > 0 do
    asked(fun, timeout, System.monotonic_time(:millisecond) + timeout, nil)
  end

  defp asked(fun, timeout, deadline, last) do
    case fun.() do
      unarrived when unarrived in [nil, false] ->
        if System.monotonic_time(:millisecond) >= deadline do
          raise "the change was not in force within #{timeout} ms; the last answer was #{inspect(last)}"
        else
          Process.sleep(@interval)
          asked(fun, timeout, deadline, unarrived)
        end

      arrived ->
        arrived
    end
  end
end
