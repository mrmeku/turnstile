defmodule Turnstile.Test.Clock do
  @moduledoc """
  The clock a test sets. `set/1` overrides the configured clock for the rest
  of the calling process and answers the moment it set, so a test that needs
  a fixed time names it once and every call the port makes reads it.

  The configured clock is a zero-arity function, so a test needs no mock and
  no behaviour of its own: what `set/1` installs is a closure over the
  moment, and `Turnstile.Config.resolve/0` finds it from the test process
  and from any process in its `$callers` chain.
  """

  @doc "Set the clock for the rest of the calling process, and answer the moment."
  @spec set(DateTime.t()) :: DateTime.t()
  def set(%DateTime{} = at) do
    :ok = Turnstile.Test.with_config(clock: fn -> at end)
    at
  end
end
