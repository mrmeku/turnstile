defmodule Turnstile.Id do
  @moduledoc "An identifier: a UUID string, the shape every subject, object, decision, and operation id has."

  alias Ecto.UUID

  @typedoc "A UUID in its canonical string form."
  @type t :: String.t()

  @doc "A fresh identifier."
  @spec new() :: t()
  def new, do: UUID.generate()

  @doc "Whether a term is an identifier in canonical form."
  @spec valid?(term()) :: boolean()
  def valid?(id) when is_binary(id), do: match?({:ok, _uuid}, UUID.cast(id))
  def valid?(_other), do: false
end
