defmodule ExampleFga.Guard do
  @moduledoc """
  The precondition the model does not carry: the marking operations require a
  session that re-authenticated inside the window, and a session is a fact
  about the call rather than about a relationship.

  Putting it in a condition would make every use of `designator` demand
  session context, including the review, which asks what a designator may do
  rather than what this caller may do now. So the operations C7 names are
  admitted only for a fresh session, and every other operation is admitted
  and left to the model.

  The window itself is the example's, read from `Example.Sessions`, which is
  where the domain states how long a re-authentication lasts.
  """

  @behaviour Turnstile.Fga.Guard

  @gated [:change_marking, :set_decontrol, :decontrol]

  @impl Turnstile.Fga.Guard
  def admits?(operation, environment) when operation in @gated, do: Example.Sessions.fresh?(environment)
  def admits?(_operation, _environment), do: true
end
