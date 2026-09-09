defmodule Turnstile.Fga.Seed do
  @moduledoc """
  How the conformance template makes this adapter's store agree with a world:
  by draining, not by writing what the world says. The template writes each
  world through the seam, so the ledger already carries it as fact events,
  and the drain is the mechanism under test rather than a shortcut around it.
  Only the events above the checkpoint are read, so a world after a world
  costs the difference.

  The fixture's items are rows and not facts: no event says which folder an
  item belongs to, so the mapping states no tuple for one and the drain
  cannot write it. The world does say it, so the seed writes those links
  itself as structure, over the one object type the mapping leaves out of
  `object_types/0`, which is why reconcile ignores them.
  """

  @behaviour Turnstile.Conformance.Seed

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Conformance, Turnstile.Fga, Turnstile.Fixture]

  alias Turnstile.Fga
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Projector
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fixture.World
  alias Turnstile.Projection.Drain

  @impl Turnstile.Conformance.Seed
  def seed(%World{} = world) do
    {:ok, projector} = Projector.resolve(Fga)
    {:ok, %Drain{}} = Projector.drain_once(projector)

    linked(projector, world)
  end

  @doc "The tuple that says which folder an item belongs to."
  @spec link(term(), term()) :: TupleKey.t()
  def link(item, folder) do
    %TupleKey{user: "folder:#{folder}", relation: "folder", object: "item:#{item}"}
  end

  defp linked(%Projector{} = projector, %World{} = world) do
    wanted = MapSet.new(world.items, fn {item, folder} -> link(item, folder) end)
    {:ok, present} = pages(projector, %Read{object_type: "item", limit: projector.batch}, [])
    have = MapSet.new(present)
    call = %Write{deletes: sorted(have, wanted), writes: sorted(wanted, have)}

    written(projector, call)
  end

  defp sorted(from, without), do: Enum.sort_by(MapSet.difference(from, without), &TupleKey.key/1)

  defp written(%Projector{}, %Write{deletes: [], writes: []}), do: :ok

  defp written(%Projector{} = projector, %Write{} = call) do
    {:ok, _count} = projector.client.write(projector.endpoint, projector.store, call)

    :ok
  end

  defp pages(%Projector{} = projector, %Read{} = request, done) do
    {:ok, %Page{} = page} = projector.client.read(projector.endpoint, projector.store, request)

    case page.continuation do
      nil -> {:ok, Enum.concat(Enum.reverse([page.tuples | done]))}
      continuation -> pages(projector, %{request | continuation: continuation}, [page.tuples | done])
    end
  end
end
