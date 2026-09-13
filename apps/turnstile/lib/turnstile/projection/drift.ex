defmodule Turnstile.Projection.Drift do
  @moduledoc "What `reconcile/1` found: what the fold requires and the state lacks, what the state has and the fold does not, and the position checked to."

  @enforce_keys [:missing, :extra, :checked_to]
  defstruct @enforce_keys

  @type t :: %__MODULE__{missing: [term()], extra: [term()], checked_to: non_neg_integer()}

  @doc "Whether nothing differs."
  @spec clean?(t()) :: boolean()
  def clean?(%__MODULE__{missing: [], extra: []}), do: true
  def clean?(%__MODULE__{}), do: false
end
