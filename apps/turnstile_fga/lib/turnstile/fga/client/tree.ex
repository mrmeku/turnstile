defmodule Turnstile.Fga.Client.Tree do
  @moduledoc """
  What `expand/3` answers: one node of the relation tree. `users` are the
  users the node holds directly, as the strings the store keeps them under,
  and `children` are the nodes it is computed from, so an explanation reads
  the path by walking down.
  """

  @enforce_keys [:object, :relation, :users]
  defstruct [:object, :relation, :users, children: []]

  @type t :: %__MODULE__{object: String.t(), relation: String.t(), users: [String.t()], children: [t()]}
end
