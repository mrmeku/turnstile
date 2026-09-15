defmodule Turnstile.Fga.Relay.Core.Key do
  @moduledoc false
  # The pair of integers a pass takes its advisory lock on.
  #
  # Postgres keeps advisory locks in one space for the whole database, and
  # the pair is all there is to tell one holder from another, so the first
  # integer stands for this library and the second for the runner. Both come
  # from `:erlang.phash2/1`, which answers the same number for the same term
  # on every node and every release, so two nodes running one runner arrive
  # at one key without agreeing on anything else.
  #
  # `phash2/1` answers below 2^27, which is inside the signed 32-bit integer
  # Postgres takes for each half of the pair.

  @class :erlang.phash2(:turnstile_relay)

  @doc "The lock a runner of this name takes."
  @spec of(atom()) :: {non_neg_integer(), non_neg_integer()}
  def of(name) when is_atom(name), do: {@class, :erlang.phash2(name)}
end
