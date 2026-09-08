defmodule Turnstile.Ledger do
  @moduledoc """
  The ledger behaviour: append fact events, read them in order from a
  position, report the head. The configured ledger is `{module, options}`;
  the options are the module's own, validated by `options_schema/0`, and are
  passed back to every callback.
  """

  alias Turnstile.Error
  alias Turnstile.FactEvent

  @type options :: keyword()
  @type failure :: {:error, Error.Engine.t()}

  @doc "Append events in order; the events come back with their positions stamped."
  @callback append(options(), [FactEvent.t()]) :: {:ok, [FactEvent.t()]} | failure()

  @doc "Events with a position above `from`, in position order, at most `limit` of them."
  @callback read(options(), from :: non_neg_integer(), limit :: pos_integer()) :: {:ok, [FactEvent.t()]} | failure()

  @doc "The head: the highest committed position, 0 for an empty ledger."
  @callback head(options()) :: {:ok, non_neg_integer()} | failure()

  @doc "The schema for the ledger's entry in `Turnstile.Config`."
  @callback options_schema() :: NimbleOptions.t()
end
