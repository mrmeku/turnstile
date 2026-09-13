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
  in: the protected schemas, the operations, the kinds of grant, the
  exemption every write declares, and the object a grant covers. The
  populations are one generator, for the properties, and four fixed worlds
  the shape, fail-closed, latency, and projection cases are written over,
  with `focus/1` naming the subject and the grant those four are built
  around. Reading a population answers what it holds and what its rule
  says. Writing one puts it in the tables, changes it there, and reads it
  back.
  """

  alias Turnstile.Ledger.Fold

  @typedoc "A population: a struct of the module that implements this behaviour."
  @type t :: struct()

  @typedoc "What a grant sits on, in whatever terms the world keeps it."
  @type grantable :: term()

  @typedoc "One change to a population, in whatever terms the world applies it."
  @type step :: term()

  @doc "Every protected schema the properties scope over."
  @callback schemas() :: [module()]

  @doc "The schema the shape cases fill with rows and scope over; one of `schemas/0`."
  @callback scope_schema() :: module()

  @doc "The operations the rule knows."
  @callback operations() :: [atom()]

  @doc "The kinds of grant the rule reads, such as the roles a membership carries."
  @callback grant_types() :: [atom()]

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

  @doc "Several subjects, several objects, one of them reached through another, and several grants: the projection cases."
  @callback layered() :: t()

  @doc "The subject the fixed worlds grant to, and what they grant it on."
  @callback focus(t()) :: {Turnstile.subject(), grantable()}

  @doc "Every subject the population knows."
  @callback subjects(t()) :: [Turnstile.subject()]

  @doc "Every object the population holds."
  @callback objects(t()) :: [Turnstile.object()]

  @doc "Everything in the population a grant can sit on."
  @callback grantables(t()) :: [grantable()]

  @doc "The rule: what the population says about one subject, operation, and object."
  @callback allowed?(t(), Turnstile.subject(), atom(), Turnstile.object()) :: boolean()

  @doc "The fold a ledger of this population's writes reaches."
  @callback facts(t()) :: %{Fold.key() => term()}

  @doc "Delete every row of the population through the seam, one at a time where the ledger must record it."
  @callback clear(module()) :: :ok

  @doc "Write the population through the seam."
  @callback insert(module(), t()) :: :ok

  @doc "The population the tables hold."
  @callback read(module()) :: t()

  @doc "Give the subject a grant of that kind, through the seam, and answer the population it leaves."
  @callback grant(module(), t(), Turnstile.subject(), grantable(), atom()) :: t()

  @doc "Take the subject's grant away, through the seam, and answer the population it leaves."
  @callback revoke(module(), t(), Turnstile.subject(), grantable()) :: t()

  @doc "Write one grant through the seam and nothing else, for the case that counts the queries a fact write costs."
  @callback insert_grant(module(), Turnstile.subject(), grantable(), atom()) :: :ok

  @doc """
  Bring the scope schema up to that many rows, none of them granted, given
  the population already written. The rows the population holds are its own
  to know: a read would go through the seam, and an adapter that binds the
  database itself answers a read no decision carries with nothing.
  """
  @callback fill(module(), t(), pos_integer()) :: :ok

  @doc "One to eight changes to the population."
  @callback steps(t()) :: StreamData.t([step()])

  @doc "Apply one change through the seam and answer the population it leaves."
  @callback apply_step(module(), t(), step()) :: t()

  @doc "The module behind a population."
  @spec module(t()) :: module()
  def module(%module{}), do: module
end
