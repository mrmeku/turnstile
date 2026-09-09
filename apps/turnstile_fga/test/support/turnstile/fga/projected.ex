defmodule Turnstile.Fga.Projected do
  @moduledoc """
  The projector as the three projection cases of Tier 1 drive it: the
  `Turnstile.Projection` callbacks are the projector's own, the disturbance
  deletes one tuple through the client so reconcile has something to report,
  and the interruption puts `Turnstile.Fga.Interrupting` in front of the
  client, which lets a write land and then fails.

  The configuration these callbacks take is a `Turnstile.Fga.Projector`
  struct, which is what the conformance module's own setup resolves and puts
  in the test context.
  """

  @behaviour Turnstile.Conformance.Projected
  @behaviour Turnstile.Projection

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Conformance, Turnstile.Fga, Turnstile.Fga.Interrupting]

  alias Turnstile.Conformance.Projected
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Interrupting
  alias Turnstile.Fga.Projector

  @impl Turnstile.Projection
  def checkpoint(%Projector{} = projector), do: Projector.checkpoint(projector)

  @impl Turnstile.Projection
  def drain_once(%Projector{} = projector), do: Projector.drain_once(projector)

  @impl Turnstile.Projection
  def rebuild(%Projector{} = projector), do: Projector.rebuild(projector)

  @impl Turnstile.Projection
  def reconcile(%Projector{} = projector), do: Projector.reconcile(projector)

  @impl Projected
  def disturb(%Projector{} = projector) do
    {:ok, [tuple | _rest]} = held(projector)
    {:ok, _count} = projector.client.write(projector.endpoint, projector.store, %Write{deletes: [tuple], writes: []})

    :ok
  end

  @impl Projected
  def interrupt(%Projector{} = projector) do
    :ok = Interrupting.through(projector.client)

    %{projector | client: Interrupting}
  end

  # The tuples of the first object type the mapping names, paged as the
  # projector pages them, so a store the drain filled has one to take away.
  defp held(%Projector{} = projector) do
    [type | _rest] = projector.mapping.object_types()

    pages(projector, %Read{object_type: type, limit: projector.batch}, [])
  end

  defp pages(%Projector{} = projector, %Read{} = request, done) do
    case projector.client.read(projector.endpoint, projector.store, request) do
      {:ok, %Page{continuation: nil} = page} -> {:ok, Enum.concat(Enum.reverse([page.tuples | done]))}
      {:ok, %Page{} = page} -> pages(projector, %{request | continuation: page.continuation}, [page.tuples | done])
      {:error, error} -> {:error, error}
    end
  end
end
