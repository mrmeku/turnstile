defmodule Turnstile.Ledger.Reader do
  @moduledoc """
  Reading a ledger from one end to the other. A ledger answers at most as
  many events as the reader asked for, so a reader pages: the next page
  starts at the position the last one ended on, and the last page is the one
  that comes back short. Replay and reconcile both read this way.
  """

  use Boundary, top_level?: true, deps: [Turnstile]

  alias Turnstile.Error
  alias Turnstile.FactEvent

  @page 1_000

  @doc "How many events one page holds."
  @spec page() :: pos_integer()
  def page, do: @page

  @doc "Every event of the ledger, the origin first and then every page above it."
  @spec all({module(), keyword()}) :: {:ok, [FactEvent.t()]} | {:error, Error.Engine.t()}
  def all({module, options}) when is_atom(module) and is_list(options) do
    with {:ok, origin} <- origin({module, options}),
         {:ok, above} <- pages({module, options}, 0, []) do
      {:ok, origin ++ above}
    end
  end

  defp origin({module, options}) do
    if function_exported?(module, :origin, 1), do: module.origin(options), else: {:ok, []}
  end

  defp pages({module, options}, from, done) do
    case module.read(options, from, @page) do
      {:ok, []} -> {:ok, Enum.concat(Enum.reverse(done))}
      {:ok, events} -> pages({module, options}, List.last(events).position, [events | done])
      {:error, error} -> {:error, error}
    end
  end
end
