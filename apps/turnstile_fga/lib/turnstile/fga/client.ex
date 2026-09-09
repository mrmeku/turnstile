defmodule Turnstile.Fga.Client do
  @moduledoc """
  The only path to the server. Every call the adapter and the projector make
  is a callback here, so a suite runs either of them against
  `Turnstile.Fga.Client.Fake` without a server, and the real client is the
  same eight calls over HTTP.

  Two arguments come before the request in every call. The endpoint is where
  the server is: the address of a real one, or the agent a fake runs on. The
  store is the isolation unit the server keeps tuples in, which is why a
  test that wants tuples of its own creates a store of its own rather than
  cleaning up after itself.

  Each call answers `{:ok, value}` or an engine error, and none of them
  raises: a server that is unreachable, a store that is absent, and a write
  the server refuses are all values the caller decides about.

  A model id is a value on the request rather than state on the client,
  because a decision is taken under a version. A request that names none
  asks under whatever the store has last published, which is what a rebuild
  does before any decision reads from that store.
  """

  alias Turnstile.Error
  alias Turnstile.Fga.Client.BatchCheck
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.Expand
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Tree
  alias Turnstile.Fga.Client.Write

  @max_tuples_per_write 100
  @max_checks_per_batch 50

  @typedoc "Where the server is: the address of one, or the process a fake runs on."
  @type endpoint :: String.t() | pid() | GenServer.name()

  @typedoc "The store tuples live in."
  @type store :: String.t()

  @typedoc "The id of a published model."
  @type model :: String.t()

  @type failure :: {:error, Error.Engine.t()}

  @doc "A store of the given name, answering the id the server gave it."
  @callback create_store(endpoint(), String.t()) :: {:ok, store()} | failure()

  @doc "The model published into the store, answering the id it was published under."
  @callback write_model(endpoint(), store(), map()) :: {:ok, model()} | failure()

  @doc "Whether one tuple holds."
  @callback check(endpoint(), store(), Check.t()) :: {:ok, boolean()} | failure()

  @doc "Whether each tuple of the batch holds, by the correlation id it was asked under."
  @callback batch_check(endpoint(), store(), BatchCheck.t()) :: {:ok, %{String.t() => boolean()}} | failure()

  @doc "The objects of one type the user holds one relation on."
  @callback list_objects(endpoint(), store(), ListObjects.t()) :: {:ok, [String.t()]} | failure()

  @doc "The tree behind one relation on one object."
  @callback expand(endpoint(), store(), Expand.t()) :: {:ok, Tree.t()} | failure()

  @doc "One page of the tuples the store holds."
  @callback read(endpoint(), store(), Read.t()) :: {:ok, Page.t()} | failure()

  @doc "The deletes and the writes of one call, applied together, answering how many changes it carried."
  @callback write(endpoint(), store(), Write.t()) :: {:ok, non_neg_integer()} | failure()

  @doc """
  How many changes one `write/3` carries, counting its deletes and its
  writes together. This is the pinned server's own limit, so the fake holds
  callers to it and the projector packs its calls under it.
  """
  @spec max_tuples_per_write() :: pos_integer()
  def max_tuples_per_write, do: @max_tuples_per_write

  @doc """
  How many checks one `batch_check/3` carries. This is the pinned server's
  own limit as well, and it is lower than the cap on identifiers a rule may
  carry, so a batch over more objects than this is more than one call.
  """
  @spec max_checks_per_batch() :: pos_integer()
  def max_checks_per_batch, do: @max_checks_per_batch

  @doc "An engine error from this adapter, naming the call it came from."
  @spec error(atom(), String.t()) :: Error.Engine.t()
  def error(operation, detail) when is_atom(operation) and is_binary(detail) do
    %Error.Engine{adapter: Turnstile.Fga, operation: operation, detail: detail}
  end
end
