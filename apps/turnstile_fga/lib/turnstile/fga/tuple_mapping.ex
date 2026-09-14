defmodule Turnstile.Fga.TupleMapping do
  @moduledoc """
  What an application states about its tables, in the terms the store keeps:
  which object types it writes, which objects of a type there are, which
  objects one change can have affected, and which tuples an object requires.

  Every answer is read from the tables through the repo it is given. A tuple
  can rest on several rows at once, so what an object requires is read from
  the rows as they stand rather than computed from the change that arrived:
  a marker says which object to look at, and the rows say what it needs.

  `tuples/2` is total: for an object whose rows are there it answers every
  tuple that object requires, and for an object whose rows are gone it
  answers none. That is what makes a drain a difference rather than a
  translation of changes into writes, what makes a marker delivered twice
  cost a read and no write, and what lets a deletion be a drain of the same
  kind as a creation.

  `changed/2` may name more objects than a change strictly affects. A drain
  of an object that needed nothing writes nothing, so an answer that is too
  wide costs a read, and an answer that is too narrow leaves the store
  behind the tables until a reconcile reports it.
  """

  alias Turnstile.Fga.TupleKey

  @typedoc "An object as the store names it: the type and the id joined by a colon."
  @type object :: String.t()

  @doc "Every object type this mapping writes tuples for, which is what a reconcile reads by."
  @callback object_types() :: [String.t()]

  @doc "Every object of one type the tables hold, which is what a rebuild and `mark_all/0` project."
  @callback objects(repo :: module(), type :: String.t()) :: [object()]

  @doc "The objects whose required tuples this change can have affected."
  @callback changed(repo :: module(), change :: map()) :: [object()]

  @doc "Every tuple the object requires in the state the tables hold."
  @callback tuples(repo :: module(), object()) :: [TupleKey.t()]
end
