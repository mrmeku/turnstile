defmodule Turnstile.Fga.TupleMapping do
  @moduledoc """
  What an application states about its facts, in the terms the store keeps:
  which object types it writes, which objects one event can have changed, and
  which tuples an object requires.

  Both questions are answered from the fold rather than from the event alone.
  An event carries what changed about one fact; a tuple can rest on several
  facts at once, so the tuples an object requires are read from the state the
  fold holds, and the objects an event touched can include objects the event
  does not name. A clearance that changes touches every object whose tuples
  carry that clearance, which the fold knows and the event does not.

  `tuples/2` is total on the fold: for an object it names, it answers every
  tuple that object requires, and for an object whose facts are gone it
  answers none. That is what makes the drain a difference rather than a
  translation of events into writes, and what makes a re-drain converge.
  """

  alias Turnstile.FactEvent
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Ledger.Fold

  @typedoc "An object as the store names it: the type and the id joined by a colon."
  @type object :: String.t()

  @doc "Every object type this mapping writes tuples for, which is what reconcile reads by."
  @callback object_types() :: [String.t()]

  @doc "The objects whose required tuples this event can have changed."
  @callback touched(Fold.t(), FactEvent.t()) :: [object()]

  @doc "Every tuple the object requires in the state the fold holds."
  @callback tuples(Fold.t(), object()) :: [TupleKey.t()]
end
