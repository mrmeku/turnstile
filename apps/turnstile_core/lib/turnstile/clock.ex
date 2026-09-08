defmodule Turnstile.Clock do
  @moduledoc "Where the port's time comes from. Tests substitute a clock; applications use `Turnstile.Clock.System`."

  @doc "The current time, in UTC."
  @callback now() :: DateTime.t()
end
