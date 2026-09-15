defmodule Turnstile.Conformance.Gen do
  @moduledoc """
  The generators the conformance properties draw from. A world-shaped one
  takes the world module, or a population and reaches its module through
  the struct, and asks that module what its rule is written in; the unknown
  operations, kinds, and subjects that must always be denied are the same
  whatever the world is.
  """

  use ExUnitProperties

  alias Turnstile.Conformance.World
  alias Turnstile.Id
  alias Turnstile.Port

  @unknown_operations [:teleport, :frobnicate, :launch]
  @unknown_kinds [:robot, :ghost, :service]

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

  @doc "An object the population holds."
  @spec object(World.t()) :: StreamData.t(Turnstile.object())
  def object(world), do: member_of(World.module(world).objects(world))

  @doc "An operation the world's rule knows."
  @spec operation(module()) :: StreamData.t(atom())
  def operation(module) when is_atom(module), do: member_of(module.operations())

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

  defp id, do: repeatedly(&Id.new/0)
end
