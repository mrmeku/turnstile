defmodule Turnstile.Ledger.Ecto.Counter do
  @moduledoc """
  The counter row: one row per named counter, holding the highest position
  handed out. Applications use the row named `default`; an async test uses
  one of its own inside its sandbox transaction. The row is what serializes
  appenders, so it is read and advanced rather than computed from the events.
  """

  use Ecto.Schema

  @primary_key {:name, :string, autogenerate: false}

  @type t :: %__MODULE__{}

  schema "turnstile_ledger_counter" do
    field :position, :integer
  end
end
