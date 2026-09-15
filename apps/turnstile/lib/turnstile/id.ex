defmodule Turnstile.Id do
  @moduledoc "An identifier: a UUID string, the shape every subject, object, decision, and operation id has."

  alias Ecto.UUID

  @typedoc "A UUID in its canonical string form."
  @type t :: String.t()

  @doc "A fresh identifier."
  @spec new() :: t()
  def new, do: UUID.generate()
end
