defmodule Turnstile.Fga.Interrupting do
  @moduledoc """
  A client that reaches the server and then loses the answer. Every call is
  the client it stands in front of, and `write/3` answers an engine error
  after that client acknowledged the write, which is the crash the projector
  has to survive: the changes are in the store and nothing advanced the
  checkpoint.

  Which client it stands in front of is the calling process's to say, so a
  test that drives a drain against a real server interrupts it without
  naming the transport here.
  """

  @behaviour Turnstile.Fga.Client

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Fga]

  alias Turnstile.Fga.Client

  @key __MODULE__

  @doc "Stand in front of this client for the rest of the calling process."
  @spec through(module()) :: :ok
  def through(client) when is_atom(client) do
    Process.put(@key, client)
    :ok
  end

  @doc "The client this one stands in front of."
  @spec behind() :: module()
  def behind, do: Process.get(@key, Client.Http)

  @impl Client
  def create_store(endpoint, name), do: behind().create_store(endpoint, name)

  @impl Client
  def write_model(endpoint, store, model), do: behind().write_model(endpoint, store, model)

  @impl Client
  def check(endpoint, store, request), do: behind().check(endpoint, store, request)

  @impl Client
  def batch_check(endpoint, store, request), do: behind().batch_check(endpoint, store, request)

  @impl Client
  def list_objects(endpoint, store, request), do: behind().list_objects(endpoint, store, request)

  @impl Client
  def expand(endpoint, store, request), do: behind().expand(endpoint, store, request)

  @impl Client
  def read(endpoint, store, request), do: behind().read(endpoint, store, request)

  @impl Client
  def write(endpoint, store, request) do
    with {:ok, count} <- behind().write(endpoint, store, request) do
      {:error, Client.error(:write, "#{count} changes were acknowledged and the answer never came back")}
    end
  end
end
