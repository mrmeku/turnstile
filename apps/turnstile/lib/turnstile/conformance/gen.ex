defmodule Turnstile.Conformance.Gen do
  @moduledoc """
  The generators the conformance properties draw from. A world-shaped one
  takes the world module, or a population and reaches its module through
  the struct, and asks that module what its rule is written in; the unknown
  operations, kinds, and subjects that must always be denied are the same
  whatever the world is; and the round trips of every struct with a map
  edge name no world at all.
  """

  use ExUnitProperties

  alias Turnstile.Answer
  alias Turnstile.Conformance.World
  alias Turnstile.Decision
  alias Turnstile.Id
  alias Turnstile.Port

  @unknown_operations [:teleport, :frobnicate, :launch]
  @unknown_kinds [:robot, :ghost, :service]
  @adapters [Turnstile.Test.Fake, Port]

  # The round trips need operations to carry, not a rule that reads them, so
  # they take a fixed list rather than a world's.
  @operations [:read, :write, :delete]

  @doc "A population of the world module."
  @spec world(module()) :: StreamData.t(World.t())
  def world(module) when is_atom(module), do: module.generator()

  @doc "A subject the population knows, of any kind the port knows."
  @spec subject(World.t()) :: StreamData.t(Turnstile.subject())
  def subject(world) do
    gen all({_kind, id} <- member_of(World.module(world).subjects(world)), kind <- member_of(Port.subject_kinds())) do
      {kind, id}
    end
  end

  @doc "A subject the population knows, as the population knows it."
  @spec grantee(World.t()) :: StreamData.t(Turnstile.subject())
  def grantee(world), do: member_of(World.module(world).subjects(world))

  @doc "Something in the population a grant can sit on."
  @spec grantable(World.t()) :: StreamData.t(World.grantable())
  def grantable(world), do: member_of(World.module(world).grantables(world))

  @doc "An object the population holds."
  @spec object(World.t()) :: StreamData.t(Turnstile.object())
  def object(world), do: member_of(World.module(world).objects(world))

  @doc "A list of the population's objects, repeats allowed."
  @spec objects(World.t()) :: StreamData.t([Turnstile.object()])
  def objects(world), do: list_of(object(world), max_length: 6)

  @doc "An operation the world's rule knows."
  @spec operation(module()) :: StreamData.t(atom())
  def operation(module) when is_atom(module), do: member_of(module.operations())

  @doc "A kind of grant the world's rule reads."
  @spec grant_type(module()) :: StreamData.t(atom())
  def grant_type(module) when is_atom(module), do: member_of(module.grant_types())

  @doc "One to eight changes to the population."
  @spec steps(World.t()) :: StreamData.t([World.step()])
  def steps(world), do: World.module(world).steps(world)

  @doc "An operation no rule knows."
  @spec unknown_operation() :: StreamData.t(atom())
  def unknown_operation, do: member_of(@unknown_operations)

  @doc "A known subject, one of an unknown kind, and one the population does not know, for deny by default."
  @spec strangers(World.t()) ::
          StreamData.t(%{subject: Turnstile.subject(), stranger: Turnstile.subject(), nobody: Turnstile.subject()})
  def strangers(world) do
    fixed_map(%{subject: subject(world), stranger: unknown_kind_subject(world), nobody: unknown_subject()})
  end

  @doc "A subject of a kind the port does not know."
  @spec unknown_kind_subject(World.t()) :: StreamData.t(Turnstile.subject())
  def unknown_kind_subject(world) do
    gen all({_kind, id} <- member_of(World.module(world).subjects(world)), kind <- member_of(@unknown_kinds)) do
      {kind, id}
    end
  end

  @doc "A subject the population does not know."
  @spec unknown_subject() :: StreamData.t(Turnstile.subject())
  def unknown_subject do
    gen all(suffix <- string(:alphanumeric, min_length: 1, max_length: 6), kind <- member_of(Port.subject_kinds())) do
      {kind, "nobody-" <> suffix}
    end
  end

  @doc "A subject with a fresh id."
  @spec subject() :: StreamData.t(Turnstile.subject())
  def subject do
    gen all(id <- id(), kind <- member_of(Port.subject_kinds())) do
      {kind, id}
    end
  end

  @doc "Any reason an answer can carry."
  @spec reason() :: StreamData.t(Answer.reason())
  def reason, do: member_of(Answer.reasons())

  @doc "A decision of any verdict."
  @spec decision() :: StreamData.t(Decision.t())
  def decision do
    %{
      id: id(),
      subject: subject(),
      object: ref(),
      operation: member_of(@operations ++ @unknown_operations),
      verdict: member_of(Decision.verdicts()),
      reason: reason(),
      adapter: member_of(@adapters),
      policy_version: one_of([constant(nil), text()]),
      operation_id: id(),
      at: time()
    }
    |> fixed_map()
    |> map(&struct!(Decision, &1))
  end

  @doc "A time with microsecond precision, as the ISO 8601 edge keeps it."
  @spec time() :: StreamData.t(DateTime.t())
  def time, do: map(integer(0..4_000_000_000_000_000), &DateTime.from_unix!(&1, :microsecond))

  defp id, do: repeatedly(&Id.new/0)

  defp text, do: string(:alphanumeric, min_length: 1, max_length: 16)

  defp ref do
    gen all(type <- member_of([:thing, :box, :note]), id <- one_of([positive_integer(), text()])) do
      {type, id}
    end
  end
end
