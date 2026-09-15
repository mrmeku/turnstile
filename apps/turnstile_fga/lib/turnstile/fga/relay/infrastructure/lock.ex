defmodule Turnstile.Fga.Relay.Infrastructure.Lock do
  @moduledoc false
  # The advisory lock one pass takes, so that two nodes running the same
  # runner do not read and deliver the same batch at once.
  #
  # The lock is transaction-scoped: Postgres releases it when the pass's
  # transaction ends, however it ends, so a node that stops holds nothing.
  # It is asked for rather than waited on, because a runner that finds
  # another node delivering has nothing useful to do with the wait: it steps
  # aside and tries again after its idle interval, by which time the rows it
  # would have delivered are usually gone.

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Fga.Relay.Domain.Key

  @exemption {:exempt, :library}

  @doc "Take the lock for the rest of the current transaction. Answers whether it was taken."
  @spec taken?(module(), atom()) :: boolean()
  def taken?(repo, name) when is_atom(repo) and is_atom(name) do
    {class, key} = Key.of(name)

    query =
      from(lock in fragment("SELECT pg_try_advisory_xact_lock(?::int, ?::int) AS taken", ^class, ^key),
        select: lock.taken
      )

    repo.one(query, turnstile: @exemption)
  end
end
