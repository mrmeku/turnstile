defmodule Turnstile.Test.AroundAdapter do
  @moduledoc """
  The fake adapter plus `around_query/3`, which sends the test process the
  query or changeset and the decision the seam handed it, then runs the
  call. Test support only.
  """

  @behaviour Turnstile.Adapter

  use Boundary, top_level?: true, deps: [Turnstile]

  alias Turnstile.Adapter.Fake

  @impl Turnstile.Adapter
  defdelegate options_schema, to: Fake

  @impl Turnstile.Adapter
  defdelegate requires_ledger, to: Fake

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
  def around_query(query_or_changeset, decision, fun) when is_function(fun, 0) do
    send(self(), {:around_query, query_or_changeset, decision})
    fun.()
  end
end
