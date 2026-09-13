defmodule Turnstile.Test.LedgerAdapter do
  @moduledoc """
  The fake adapter that requires a ledger, which is what an adapter whose
  state is a projection of the ledger declares. Everything else is the
  fake's: the point of this module is the declaration, so the template's
  shape cases for such an adapter have one to run against. Test support
  only.

  The projection it declares is whatever `bind/1` put in the calling
  process, the way a real adapter resolves its projector from its binding,
  and `:none` until something does.
  """

  @behaviour Turnstile.Adapter

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Test.Projection]

  alias Turnstile.Adapter.Fake
  alias Turnstile.Test.Projection

  @impl Turnstile.Adapter
  defdelegate options_schema, to: Fake

  @impl Turnstile.Adapter
  def requires_ledger, do: true

  @impl Turnstile.Adapter
  defdelegate scope_cap, to: Fake

  @impl Turnstile.Adapter
  defdelegate authorize(subject, operation, object, environment, options), to: Fake

  @impl Turnstile.Adapter
  defdelegate check(subject, operation, object, environment, options), to: Fake

  @impl Turnstile.Adapter
  defdelegate batch(subject, operation, objects, environment, options), to: Fake

  @impl Turnstile.Adapter
  defdelegate scope(subject, operation, object_type, environment, options), to: Fake

  @impl Turnstile.Adapter
  defdelegate explain(subject, operation, object, environment, options), to: Fake

  @impl Turnstile.Adapter
  def projection do
    case Process.get(__MODULE__) do
      nil -> :none
      %Projection{} = projection -> {:ok, {Projection, projection}}
    end
  end

  @doc "The projection this adapter declares for the rest of the calling process."
  @spec bind(Projection.t()) :: :ok
  def bind(%Projection{} = projection) do
    Process.put(__MODULE__, projection)
    :ok
  end
end
