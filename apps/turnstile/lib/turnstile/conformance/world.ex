defmodule Turnstile.Conformance.World do
  @moduledoc """
  The population a Tier 1 run is written over, supplied by the caller.
  `use Turnstile.Conformance.AdapterCase, world: MyApp.World` hands the
  template a module that answers what a population holds, what the rule
  over it says, and how to write one through the seam, and the properties
  and the laws ask that module for everything they need. Core names no
  schema of its own and no rule of its own, so an adapter outside this
  repository proves itself against its own tables.

  A population is a struct of the module that implements this behaviour, so
  a law handed one reaches the module through the struct and carries no
  second argument. `module/1` is that step.

  The callbacks fall in four groups. The shape is what the rule is written
  in: the protected schemas, the operations, the exemption every write
  declares, and the object a grant covers. The populations are one
  generator, for the properties, and three fixed worlds the shape,
  fail-closed, and latency cases are written over, with `focus/1` naming
  the subject and the grant those three are built around. Reading a
  population answers what it holds, what its rule says, and which values
  its rule reads, where `subjects/1` includes one of kind `:privileged` so a
  law can ask about that kind.
  Writing one puts it in the tables, adds a grant with attributes such as
  its expiry, takes a grant out, and changes the account fact the rule
  reads; each answers the population it leaves.
  """

  @typedoc "A population: a struct of the module that implements this behaviour."
  @type t :: struct()

  @typedoc "What a grant sits on, in whatever terms the world keeps it."
  @type grantable :: term()

  @doc "Every protected schema the properties scope over."
  @callback schemas() :: [module()]

  @doc "The schema the shape cases fill with rows and scope over; one of `schemas/0`."
  @callback scope_schema() :: module()

  @doc "The operations the rule knows."
  @callback operations() :: [atom()]

  @doc "The exemption every write of a population declares through the seam."
  @callback exemption() :: term()

  @doc "The object a grant on this thing covers."
  @callback object_of(grantable()) :: Turnstile.object()

  @doc "A random population, for the properties."
  @callback generator() :: StreamData.t(t())

  @doc "One subject, one object, one grant: the world the fail-closed and latency cases run over."
  @callback granted() :: t()

  @doc "The same population with the grant taken out, for the case that writes one fact and counts the queries."
  @callback ungranted() :: t()

  @doc "`granted/0` with more objects in the scope schema than the grant covers, for the shape cases."
  @callback scoped() :: t()

  @doc "The subject the fixed worlds grant to, which is a user, and what they grant it on."
  @callback focus(t()) :: {Turnstile.subject(), grantable()}

  @doc "Every subject the population knows, including one of kind `:privileged`."
  @callback subjects(t()) :: [Turnstile.subject()]

  @doc "Every object the population holds."
  @callback objects(t()) :: [Turnstile.object()]

  @doc """
  Every attribute value the population holds that a rule reads: the
  clearances, the roles, the expiries, and whatever else a fact column
  carries, with nothing in the list that a decision event would carry of
  its own, such as a subject kind. A law refutes each of these in the
  decision events, so a value here that is also a subject id, an object id,
  or a verdict would fail that law for the wrong reason.
  """
  @callback facts(t()) :: [term()]

  @doc "The rule: what the population says about one subject, operation, and object."
  @callback allowed?(t(), Turnstile.subject(), atom(), Turnstile.object()) :: boolean()

  @doc "Delete every row of the population through the seam, one row at a time, so the seam records each."
  @callback clear(module()) :: :ok

  @doc "Write the population through the seam."
  @callback insert(module(), t()) :: :ok

  @doc "Take the subject's grant away, through the seam, and answer the population it leaves."
  @callback revoke(module(), t(), Turnstile.subject(), grantable()) :: t()

  @doc """
  Write one grant to the subject on the grantable through the seam and
  nothing else, with the attributes given, of which `expires_at` is the one
  the laws set, and answer the population it leaves. One write, so the case
  that counts the queries a fact write costs can count it.
  """
  @callback insert_grant(module(), t(), Turnstile.subject(), grantable(), keyword()) :: t()

  @doc "Change the account fact the rule reads so the subject no longer satisfies it, and answer the population."
  @callback disqualify(module(), t(), Turnstile.subject()) :: t()

  @doc """
  Bring the scope schema up to that many rows, none of them granted, given
  the population already written. The rows the population holds are its own
  to know: a read would go through the seam, and an adapter that binds the
  database itself answers a read no decision carries with nothing.
  """
  @callback fill(module(), t(), pos_integer()) :: :ok

  @doc "The module behind a population."
  @spec module(t()) :: module()
  def module(%module{}), do: module
end
