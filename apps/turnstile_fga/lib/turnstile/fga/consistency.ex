defmodule Turnstile.Fga.Consistency do
  @moduledoc """
  What a call asks of the store's replication. `:minimize_latency` takes
  what is at hand, `:higher_consistency` waits for what was written, and
  `:unspecified` leaves the choice to the server's own default.

  Which one an operation takes is a constant of this adapter rather than an
  option an application sets, so the field on a request carries the choice
  and no caller passes it in.
  """

  @typedoc "The three the server knows."
  @type t :: :unspecified | :minimize_latency | :higher_consistency
end
