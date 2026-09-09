defmodule Turnstile.Fga.Client.Page do
  @moduledoc """
  One page of tuples and what to ask for the next: a continuation of
  nothing is the last page, which is how a caller knows it has read an
  object whole.
  """

  alias Turnstile.Fga.TupleKey

  @enforce_keys [:tuples, :continuation]
  defstruct @enforce_keys

  @type t :: %__MODULE__{tuples: [TupleKey.t()], continuation: String.t() | nil}
end
