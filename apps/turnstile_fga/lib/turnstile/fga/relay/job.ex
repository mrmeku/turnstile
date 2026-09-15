defmodule Turnstile.Fga.Relay.Job do
  @moduledoc """
  What a runner delivers: where the rows are, and what delivering a batch
  means. A job is the only part of a relay that knows what a row holds.

  Both callbacks are given the runner's repo and the job's own validated
  options. They run inside the pass's transaction, so a job that reads its
  rows through that repo reads them on the connection the cursor is advanced
  on, and a job that deletes what it delivered deletes it in the same
  transaction.

  `deliver/3` is called with the batch `read/4` answered, in the order it
  was read, and it is called again with the same batch after a pass that
  did not commit. Delivery is at least once, so a job either tolerates a
  repeat or makes one harmless at the far end.

  The term a failure carries is the job's own. The relay puts it on the pass
  event and waits longer before the next pass, and reads nothing in it.
  """

  alias Turnstile.Fga.Relay.Entry

  @type options :: keyword()
  @type failure :: {:error, term()}

  @doc "Entries above `from`, in position order, at most `limit` of them."
  @callback read(repo :: module(), options(), from :: non_neg_integer(), limit :: pos_integer()) ::
              {:ok, [Entry.t()]} | failure()

  @doc "Deliver one batch, in the order it was read."
  @callback deliver(repo :: module(), options(), [Entry.t()]) :: :ok | failure()

  @doc "The schema of the job's own options, which the runner validates at its start."
  @callback options_schema() :: NimbleOptions.t()
end
