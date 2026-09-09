defmodule Turnstile.Fga.Probe do
  @moduledoc """
  Fact events over the neutral fixture, built by hand and appended to a
  ledger in memory. The projector's own cases need positions and a fold, not
  tables, so the probe states the events the seam would write for a
  membership granted, changed, and revoked, for a clearance set, changed, and
  taken away, and for a published version, in the shapes
  `Turnstile.Fixture.World.facts/1` documents.
  """

  use Boundary, top_level?: true, deps: [Turnstile]

  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject

  @at ~U[2026-09-09 00:00:00.000000Z]
  @by %Subject{id: "probe", kind: :non_person_entity}

  @doc "A ledger of its own, empty, as the projector takes it."
  @spec ledger() :: {module(), keyword()}
  def ledger do
    {:ok, agent} = Memory.start_link()
    {Memory, agent: agent}
  end

  @doc "Append the events, answering them with their positions stamped."
  @spec append({module(), keyword()}, [FactEvent.t()]) :: [FactEvent.t()]
  def append({module, options}, events) do
    {:ok, stamped} = module.append(options, events)
    stamped
  end

  @doc "The account is given the role on the folder: the membership's existence."
  @spec granted(String.t(), pos_integer(), atom()) :: FactEvent.t()
  def granted(account, folder, role), do: membership(account, folder, nil, nil, role)

  @doc "The role of a membership that is there already changes."
  @spec changed(String.t(), pos_integer(), atom(), atom()) :: FactEvent.t()
  def changed(account, folder, from, to), do: membership(account, folder, :role, from, to)

  @doc "The membership goes."
  @spec revoked(String.t(), pos_integer(), atom()) :: FactEvent.t()
  def revoked(account, folder, role), do: membership(account, folder, nil, role, nil)

  @doc "The account's clearance moves from one value to another, either of which may be nothing."
  @spec clearance(String.t(), String.t() | nil, String.t() | nil) :: FactEvent.t()
  def clearance(account, from, to) do
    event(:subject_attribute, {:user, account}, nil, :clearance, from, to)
  end

  @doc "A published version, which states no fact."
  @spec published(String.t()) :: FactEvent.t()
  def published(version) do
    published = %PolicyVersion{
      adapter: Turnstile.Fga,
      version: version,
      content_hash: "hash-" <> version,
      author: "probe",
      approval: "probe",
      at: @at
    }

    event(:policy_version, nil, {:policy, Turnstile.Fga}, :version, nil, published)
  end

  defp membership(account, folder, attribute, old, new) do
    event(:relationship, {:user, account}, {:folder, folder}, attribute, old, new)
  end

  defp event(kind, subject_ref, object_ref, attribute, old, new) do
    %FactEvent{
      kind: kind,
      subject_ref: subject_ref,
      object_ref: object_ref,
      attribute: attribute,
      old: old,
      new: new,
      position: nil,
      operation_id: "probe-" <> Integer.to_string(System.unique_integer([:positive])),
      at: @at,
      by: @by
    }
  end
end
