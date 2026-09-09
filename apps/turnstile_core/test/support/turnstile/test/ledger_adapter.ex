defmodule Turnstile.Test.LedgerAdapter do
  @moduledoc """
  The fake adapter that requires a ledger, which is what an adapter whose
  state is a projection of the ledger declares. Everything else is the
  fake's: the point of this module is the declaration, so the template's
  shape cases for such an adapter have one to run against. Test support
  only.
  """

  @behaviour Turnstile.Adapter

  use Boundary, top_level?: true, deps: [Turnstile]

  alias Turnstile.Adapter.Fake

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
end
