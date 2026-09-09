defmodule Example.Sessions do
  @moduledoc """
  Re-authentication (C8). The window is the organization's parameter for
  IA-11; a session is fresh when the caller's `reauthenticated_at` fact is
  within the window of the port's clock. The fact is supplied by the caller,
  from the identity layer, and read by the adapter; this module is what the
  adapters that compute in code call.
  """

  alias Turnstile.Environment

  @window 900

  @doc "The re-authentication window in seconds."
  @spec window() :: pos_integer()
  def window, do: @window

  @doc "Whether the environment's `reauthenticated_at` fact is within the window of its clock."
  @spec fresh?(Environment.t()) :: boolean()
  def fresh?(%Environment{now: %DateTime{} = now, facts: facts}) when is_map(facts) do
    case facts[:reauthenticated_at] do
      %DateTime{} = at -> DateTime.diff(now, at, :second) in 0..@window
      _absent -> false
    end
  end
end
