defmodule Turnstile.Explanation do
  @moduledoc "An answer with the rules, clauses, or path that produced it, where the adapter can name them."

  @enforce_keys [:answer, :matched]
  defstruct [:answer, :matched]

  @type t :: %__MODULE__{answer: Turnstile.Answer.t(), matched: [String.t()]}
end
