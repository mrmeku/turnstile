defmodule Turnstile.Fga.Relay.Core.Backoff do
  @moduledoc false
  # How long the runner waits before its next pass, and how many failures in
  # a row it has counted.
  #
  # A full batch means the rows that follow it are already waiting, so the
  # next pass runs at once. A pass that delivered less than a batch, and one
  # that stepped aside because another node held the lock, wait the idle
  # interval. A failure waits the backoff, doubled once for each failure
  # that came before it and capped, so a database that is down is asked
  # about every half minute rather than every second, and one success puts
  # the count back to zero.
  #
  # The doubling is capped at sixteen failures as well as at the longest
  # wait, so the number this arithmetic works on stays small however long an
  # outage lasts.

  alias Turnstile.Fga.Relay.Pass

  @doublings 16

  @doc "The milliseconds before the next pass, from what this one did and the failures before it."
  @spec wait({:ok, Pass.t()} | {:error, term()}, non_neg_integer(), keyword()) :: non_neg_integer()
  def wait({:ok, %Pass{more?: true}}, _failures, _options), do: 0
  def wait({:ok, %Pass{}}, _failures, options), do: options[:idle]

  def wait({:error, _reason}, failures, options) when is_integer(failures) and failures >= 0 do
    min(options[:backoff] * Integer.pow(2, min(failures, @doublings)), options[:backoff_max])
  end

  @doc "The count of failures in a row after this pass."
  @spec failures({:ok, Pass.t()} | {:error, term()}, non_neg_integer()) :: non_neg_integer()
  def failures({:ok, %Pass{}}, _failures), do: 0
  def failures({:error, _reason}, failures) when is_integer(failures) and failures >= 0, do: failures + 1
end
