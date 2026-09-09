defmodule Turnstile.Fga.Checkpoint do
  @moduledoc """
  How far the projector has drained one store: one row per store, holding
  the position of the last event whose tuples the store carries.

  The row lives in the application's own database rather than in the store,
  because the store holds tuples and nothing else, and a checkpoint that
  lived beside them could not be advanced in step with a write the server
  acknowledged. A store no row names stands at zero, which is where genesis
  sits, so a first drain reads the whole ledger.

  The table is no fact table: it states nothing about a subject or an object,
  so writes to it carry the library exemption rather than a decision.
  """

  use Ecto.Schema

  import Ecto.Query, only: [from: 2]

  @primary_key {:store, :string, autogenerate: false}
  @exemption {:exempt, :library}

  @type t :: %__MODULE__{}

  schema "turnstile_fga_checkpoint" do
    field :position, :integer
  end

  @doc "The position the store has been drained to, zero when no row names it."
  @spec position(module(), String.t()) :: non_neg_integer()
  def position(repo, store) when is_atom(repo) and is_binary(store) do
    query = from c in __MODULE__, where: c.store == ^store, select: c.position

    repo.one(query, turnstile: @exemption) || 0
  end

  @doc "Record the store as drained to this position."
  @spec advance(module(), String.t(), non_neg_integer()) :: :ok
  def advance(repo, store, position) when is_atom(repo) and is_binary(store) and is_integer(position) do
    entry = %{store: store, position: position}
    options = [on_conflict: {:replace, [:position]}, conflict_target: :store, turnstile: @exemption]
    {_count, nil} = repo.insert_all(__MODULE__, [entry], options)

    :ok
  end
end
