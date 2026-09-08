defmodule Turnstile.Scope do
  @moduledoc """
  What an adapter answers to `scope`: the rule as an `Ecto.Query.dynamic`
  that can only narrow a query over the object type, and the answer that
  goes with it. Under a denied precondition the rule is `dynamic([_], false)`.
  """

  @enforce_keys [:rule, :answer]
  defstruct [:rule, :answer]

  @type t :: %__MODULE__{rule: Ecto.Query.dynamic_expr(), answer: Turnstile.Answer.t()}
end
