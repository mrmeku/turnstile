defmodule Turnstile.Fga.Seed do
  @moduledoc """
  How the conformance template makes this adapter's store agree with a world:
  by marking every object and draining, not by writing what the world says.
  The template writes each world through the seam, so the tables already
  carry it, and the drain is the mechanism under test rather than a shortcut
  around it. Each object costs a read and the difference, so a world after a
  world writes only what changed.

  Marking is done here rather than left to the change handler, because the
  template counts the queries a write costs and a handler writing a marker
  inside that write would be one more. What the handler does instead is
  `Turnstile.Fga.OutboxCase`'s to hold.

  The fixture's items are rows the mapping states no tuple for, since an
  item answers as its folder does and the model reaches the folder through a
  tuple of its own. The world does say which folder each item is in, so the
  seed writes those links itself as structure, over the one object type the
  mapping leaves out of `object_types/0`, which is why reconcile ignores
  them.
  """

  @behaviour Turnstile.Conformance.Seed

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Conformance, Turnstile.Fga, Turnstile.Fixture]

  alias Turnstile.Config
  alias Turnstile.Fga
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fixture.World

  @batch 100

  @impl Turnstile.Conformance.Seed
  def seed(%World{} = world) do
    :ok = Fga.mark_all()
    :ok = Fga.settle()

    linked(server(), world)
  end

  @doc "The tuple that says which folder an item belongs to."
  @spec link(term(), term()) :: TupleKey.t()
  def link(item, folder) do
    %TupleKey{user: "folder:#{folder}", relation: "folder", object: "item:#{item}"}
  end

  defp linked(server, %World{} = world) do
    wanted = MapSet.new(world.items, fn {item, folder} -> link(item, folder) end)
    {:ok, present} = pages(server, %Read{object_type: "item", limit: @batch}, [])
    have = MapSet.new(present)
    call = %Write{deletes: sorted(have, wanted), writes: sorted(wanted, have)}

    written(server, call)
  end

  defp sorted(from, without), do: Enum.sort_by(MapSet.difference(from, without), &TupleKey.key/1)

  defp written(_server, %Write{deletes: [], writes: []}), do: :ok

  defp written(server, %Write{} = call) do
    {:ok, _count} = server.client.write(server.endpoint, server.store, call)

    :ok
  end

  defp pages(server, %Read{} = request, done) do
    {:ok, %Page{} = page} = server.client.read(server.endpoint, server.store, request)

    case page.continuation do
      nil -> {:ok, Enum.concat(Enum.reverse([page.tuples | done]))}
      continuation -> pages(server, %{request | continuation: continuation}, [page.tuples | done])
    end
  end

  # Where the configured entry says the store is, which is the store the
  # drain has filled and the store every decision of the run reads.
  defp server do
    {:ok, %Config{} = config} = Config.resolve()
    {Fga, options} = Config.adapter(config)

    %{
      client: Keyword.get(options, :client, Http),
      endpoint: Keyword.fetch!(options, :endpoint),
      store: Keyword.fetch!(options, :store_id)
    }
  end
end
