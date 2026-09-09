defmodule Turnstile.Fga.Guard do
  @moduledoc """
  A precondition on the environment, asked before any question goes to the
  server. Where the binding names a guard, every callback consults it first:
  an operation the guard does not admit is denied where it stands, and the
  store is not asked.

  This is where a fact about the call belongs that no tuple should carry. A
  condition on a tuple is evaluated against the context of every question
  that walks that tuple, so a fact needed for one operation would become a
  fact every use of the relation demands, and a question asked without it
  would fail rather than answer. A guard keeps such a fact on this side of
  the call, where the operation it applies to is known.

  A guard is asked with the operation and the environment alone. It sees no
  subject and no object, because a precondition that depends on either is a
  rule of the model, where the graph can walk it.
  """

  alias Turnstile.Environment

  @doc """
  Whether this operation is admitted under this environment. A guard answers
  a boolean and nothing else: a guard that cannot tell is a guard that does
  not admit.
  """
  @callback admits?(operation :: atom(), environment :: Environment.t()) :: boolean()
end
