defmodule Turnstile.Test.SettlingAdapter do
  @moduledoc """
  The fake adapter that declares `settle/0`, which is what an adapter with
  state of its own to bring into step declares. Everything else is the
  fake's: the point of this module is the declaration, so a template's cases
  for such an adapter have one to run against. Test support only.

  What settling does is whatever `bind/1` put in the calling process, the way
  a real adapter reaches its own state through its binding, and `:none` until
  something does.
  """

  @behaviour Turnstile.Adapter

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Test]

  alias Turnstile.Error
  alias Turnstile.Test.Fake

  @impl Turnstile.Adapter
  defdelegate options_schema, to: Fake

  @impl Turnstile.Adapter
  defdelegate scope_cap, to: Fake

  @impl Turnstile.Adapter
  defdelegate decide(subject, operation, object, environment, options), to: Fake

  @impl Turnstile.Adapter
  defdelegate scope(subject, operation, object_type, environment, options), to: Fake

  @impl Turnstile.Adapter
  def settle do
    case Process.get(__MODULE__) do
      nil -> :none
      settling -> settling.()
    end
  end

  @doc "What settling this adapter does for the rest of the calling process."
  @spec bind((-> :ok | {:error, Error.t()})) :: :ok
  def bind(settling) when is_function(settling, 0) do
    Process.put(__MODULE__, settling)
    :ok
  end
end
