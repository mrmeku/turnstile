defmodule Turnstile.Conformance.Gen do
  @moduledoc """
  The generators the conformance properties draw from: worlds of the
  neutral fixture and the subjects, objects, and operations inside one;
  the unknown operations, kinds, and subjects that must always be denied;
  sequences of grants, revocations, and clearance changes; and every
  struct that has a map edge, for the round trips.
  """

  use ExUnitProperties

  alias Turnstile.Decision
  alias Turnstile.FactEvent
  alias Turnstile.Fixture.World
  alias Turnstile.Id
  alias Turnstile.Object
  alias Turnstile.PolicyVersion
  alias Turnstile.Reason
  alias Turnstile.Subject

  @accounts ~w(acct-a acct-b acct-c)
  @unknown_operations [:teleport, :frobnicate, :launch]
  @unknown_kinds [:robot, :ghost, :service]
  @adapters [Turnstile.Adapter.Fake, Turnstile.Port]

  @typedoc "One change to a world: a grant, a revocation, or a clearance change."
  @type step ::
          {:grant, String.t(), pos_integer(), :reader | :editor}
          | {:revoke, String.t(), pos_integer()}
          | {:clearance, String.t(), String.t() | nil}

  @doc "A world: one to three accounts, one to three folders, up to four items and memberships."
  @spec world() :: StreamData.t(World.t())
  def world do
    bind(population(), fn {accounts, folder_count} ->
      items = list_of(integer(1..folder_count), max_length: 4)
      grants = list_of(tuple({member_of(Map.keys(accounts)), integer(1..folder_count), role()}), max_length: 4)
      map(tuple({items, grants}), &build_world(accounts, folder_count, &1))
    end)
  end

  @doc "A clearance, permitting three times in four."
  @spec clearance() :: StreamData.t(String.t() | nil)
  def clearance, do: frequency([{3, constant(World.cleared())}, {1, constant(nil)}])

  @doc "A membership role."
  @spec role() :: StreamData.t(:reader | :editor)
  def role, do: member_of([:reader, :editor])

  @doc "A subject the world knows, of any kind."
  @spec subject(World.t()) :: StreamData.t(Subject.t())
  def subject(%World{} = world) do
    gen all(id <- member_of(World.subjects(world)), kind <- member_of(Subject.kinds())) do
      %Subject{id: id, kind: kind}
    end
  end

  @doc "An account the world knows."
  @spec account(World.t()) :: StreamData.t(String.t())
  def account(%World{} = world), do: member_of(World.subjects(world))

  @doc "A folder the world holds."
  @spec folder(World.t()) :: StreamData.t(pos_integer())
  def folder(%World{} = world), do: member_of(world.folders)

  @doc "An object the world holds."
  @spec object(World.t()) :: StreamData.t(Object.t())
  def object(%World{} = world), do: member_of(World.objects(world))

  @doc "A list of the world's objects, repeats allowed."
  @spec objects(World.t()) :: StreamData.t([Object.t()])
  def objects(%World{} = world), do: list_of(object(world), max_length: 6)

  @doc "An operation the rule knows."
  @spec operation() :: StreamData.t(atom())
  def operation, do: member_of(World.operations())

  @doc "An operation no rule knows."
  @spec unknown_operation() :: StreamData.t(atom())
  def unknown_operation, do: member_of(@unknown_operations)

  @doc "A known subject, one of an unknown kind, and one the world does not know, for deny by default."
  @spec strangers(World.t()) :: StreamData.t(%{subject: Subject.t(), stranger: Subject.t(), nobody: Subject.t()})
  def strangers(%World{} = world) do
    fixed_map(%{subject: subject(world), stranger: unknown_kind_subject(world), nobody: unknown_subject()})
  end

  @doc "A subject of a kind the port does not know."
  @spec unknown_kind_subject(World.t()) :: StreamData.t(Subject.t())
  def unknown_kind_subject(%World{} = world) do
    gen all(id <- member_of(World.subjects(world)), kind <- member_of(@unknown_kinds)) do
      %Subject{id: id, kind: kind}
    end
  end

  @doc "A subject the world does not know."
  @spec unknown_subject() :: StreamData.t(Subject.t())
  def unknown_subject do
    gen all(suffix <- string(:alphanumeric, min_length: 1, max_length: 6), kind <- member_of(Subject.kinds())) do
      %Subject{id: "nobody-" <> suffix, kind: kind}
    end
  end

  @doc "One to eight changes to the world's memberships and clearances."
  @spec steps(World.t()) :: StreamData.t([step()])
  def steps(%World{} = world), do: list_of(step(world), min_length: 1, max_length: 8)

  @doc "A subject with a fresh id."
  @spec subject() :: StreamData.t(Subject.t())
  def subject do
    gen all(id <- id(), kind <- member_of(Subject.kinds()), session <- one_of([constant(nil), id()])) do
      %Subject{id: id, kind: kind, session_id: session}
    end
  end

  @doc "A reason with any code."
  @spec reason() :: StreamData.t(Reason.t())
  def reason do
    gen all(
          code <- member_of(Reason.codes()),
          message <- string(:printable, min_length: 1, max_length: 40),
          rule <- one_of([constant(nil), string(:alphanumeric, min_length: 1, max_length: 12)])
        ) do
      %Reason{code: code, message: message, rule: rule}
    end
  end

  @doc "A policy version, with content by value or by pointer."
  @spec policy_version() :: StreamData.t(PolicyVersion.t())
  def policy_version do
    %{
      adapter: member_of(@adapters),
      version: text(),
      content_hash: text(),
      content: one_of([constant(nil), text()]),
      pointer: one_of([constant(nil), text()]),
      author: text(),
      approval: text(),
      at: time()
    }
    |> fixed_map()
    |> map(&struct!(PolicyVersion, &1))
  end

  @doc "A decision of any verdict."
  @spec decision() :: StreamData.t(Decision.t())
  def decision do
    %{
      id: id(),
      subject: subject(),
      object: ref(),
      operation: member_of(World.operations() ++ @unknown_operations),
      verdict: member_of(Decision.verdicts()),
      reason: reason(),
      adapter: member_of(@adapters),
      policy_version: one_of([constant(nil), text()]),
      head_position: one_of([constant(nil), positive_integer()]),
      operation_id: id(),
      at: time()
    }
    |> fixed_map()
    |> map(&struct!(Decision, Map.put(&1, :applied_position, &1.head_position)))
  end

  @doc "A fact event of any kind, a policy-version event carrying versions as its values."
  @spec fact_event() :: StreamData.t(FactEvent.t())
  def fact_event do
    bind(member_of(FactEvent.kinds()), fn kind ->
      %{
        kind: constant(kind),
        subject_ref: one_of([constant(nil), ref()]),
        object_ref: one_of([constant(nil), ref()]),
        attribute: one_of([constant(nil), member_of([:role, :clearance, :level])]),
        values: values(kind),
        position: one_of([constant(nil), positive_integer()]),
        operation_id: id(),
        at: time(),
        by: subject()
      }
      |> fixed_map()
      |> map(&event_of/1)
    end)
  end

  @doc "A time with microsecond precision, as the ISO 8601 edge keeps it."
  @spec time() :: StreamData.t(DateTime.t())
  def time, do: map(integer(0..4_000_000_000_000_000), &DateTime.from_unix!(&1, :microsecond))

  defp population do
    accounts = list_of(tuple({member_of(@accounts), clearance()}), min_length: 1, max_length: 3)
    tuple({map(accounts, &Map.new/1), integer(1..3)})
  end

  defp build_world(accounts, folder_count, {item_folders, grants}) do
    items =
      item_folders
      |> Enum.with_index(1)
      |> Map.new(fn {folder, item} -> {item, folder} end)

    memberships = Map.new(grants, fn {account, folder, role} -> {{account, folder}, role} end)
    %World{accounts: accounts, folders: Enum.to_list(1..folder_count), items: items, memberships: memberships}
  end

  defp event_of(%{values: {old, new}} = fields) do
    fields
    |> Map.delete(:values)
    |> Map.merge(%{old: old, new: new})
    |> then(&struct!(FactEvent, &1))
  end

  defp step(%World{} = world) do
    account = member_of(World.subjects(world))
    folder = member_of(world.folders)

    one_of([
      tuple({constant(:grant), account, folder, role()}),
      tuple({constant(:revoke), account, folder}),
      tuple({constant(:clearance), account, clearance()})
    ])
  end

  defp id, do: repeatedly(&Id.new/0)

  defp text, do: string(:alphanumeric, min_length: 1, max_length: 16)

  defp ref do
    gen all(type <- member_of([:folder, :item, :thing]), id <- one_of([positive_integer(), text()])) do
      {type, id}
    end
  end

  defp values(:policy_version), do: tuple({one_of([constant(nil), policy_version()]), policy_version()})
  defp values(_kind), do: tuple({plain(), plain()})

  defp plain, do: one_of([constant(nil), text(), integer()])
end
