defmodule Turnstile.Object do
  @moduledoc "What the subject asks about: an object type and an id."

  @enforce_keys [:type, :id]
  defstruct [:type, :id]

  @typedoc "The compact form a decision record and a fact event carry."
  @type ref :: {atom(), Turnstile.Id.t()}

  @type t :: %__MODULE__{type: atom(), id: Turnstile.Id.t()}

  @doc "The object's reference."
  @spec ref(t()) :: ref()
  def ref(%__MODULE__{type: type, id: id}), do: {type, id}
end
