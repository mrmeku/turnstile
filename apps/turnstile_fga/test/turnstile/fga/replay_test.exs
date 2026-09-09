defmodule Turnstile.Fga.ReplayTest do
  use ExUnit.Case, async: true

  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Probe
  alias Turnstile.Fga.Replay
  alias Turnstile.Fixture.World
  alias Turnstile.Id
  alias Turnstile.Reason
  alias Turnstile.Subject
  alias Turnstile.Test

  @model "priv/conformance/model.fga"

  # A ledger whose facts move: the membership is granted, the clearance is
  # set, and then the membership is revoked. The cut before the revocation is
  # the state a stored decision was answered from, and the state after it is
  # the present.
  setup do
    ledger = Probe.ledger()

    [granted, cleared, revoked] =
      Probe.append(ledger, [
        Probe.granted("ann", 1, :reader),
        Probe.clearance("ann", nil, World.cleared()),
        Probe.revoked("ann", 1, :reader)
      ])

    {:ok, ledger: ledger, granted: granted.position, cleared: cleared.position, revoked: revoked.position}
  end

  test "a stored decision asked again against the state it names answers as the record does", context do
    server = Test.Fga.start_supervised!()
    stored = decision(:allow, context.cleared)

    assert {:ok, replay} = build(server.address, context, context.cleared)
    assert {:ok, %Answer{} = answer} = Replay.ask(replay, stored)
    assert answer.verdict == stored.verdict
    assert answer.reason == Reason.allowed("can_read")
    assert answer.applied_position == context.cleared

    # The id belongs to the store that issued it, so what the two share is the
    # text the version event carries rather than the id.
    assert is_binary(answer.policy_version)
    refute answer.policy_version == stored.policy_version

    assert {:ok, present} = build(server.address, context, context.revoked)
    assert {:ok, %Answer{} = denied} = Replay.ask(present, stored)
    assert denied.verdict == :deny
    assert denied.reason == Reason.deny_by_default()
    assert denied.applied_position == context.revoked
  end

  test "the fold is written into the throwaway store in calls of the size the caller states", context do
    agent = start_supervised!(Fake)

    assert {:ok, replay} =
             Replay.build(
               client: Fake,
               endpoint: agent,
               model: File.read!(@model),
               mapping: Mapping,
               ledger: context.ledger,
               to: context.cleared,
               batch: 1
             )

    assert replay.store == "store-1"
    assert replay.position == context.cleared
    assert Enum.map(Fake.writes(agent), &length(&1.writes)) == [1, 1]

    held = Enum.map(Fake.tuples(agent, replay.store), & &1.object)
    assert held == ["clearance:cleared", "folder:1"]
  end

  test "a store the throwaway server refuses to make is an engine error", context do
    assert {:error, %Error.Engine{} = error} = build("127.0.0.1:1", context, context.cleared)
    assert error.adapter == Turnstile.Fga
    assert error.operation == :create_store
  end

  test "a model text that does not compile loads nothing", context do
    agent = start_supervised!(Fake)
    options = [client: Fake, endpoint: agent, model: "not a model", mapping: Mapping, ledger: context.ledger, to: 0]

    assert {:error, %Error.Invalid{what: :model} = error} = Replay.build(options)
    assert error.detail == "a model opens with a model line and a schema line"
    assert Fake.calls(agent) == []
  end

  test "the options a build takes name the client, the server, the model, the mapping, the ledger, and the cut" do
    schema = Replay.options_schema().schema

    for field <- [:client, :endpoint, :model, :mapping, :ledger, :to], do: assert(schema[field][:required])
    assert schema[:store_name][:default] == "turnstile-replay"
    refute schema[:batch][:required]

    assert {:error, %Error.Invalid{what: :replay} = error} = Replay.build(client: Fake)
    assert error.detail =~ "required :endpoint option not found"
  end

  defp build(address, context, to) do
    Replay.build(
      client: Http,
      endpoint: address,
      store_name: "replay-#{System.unique_integer([:positive])}",
      model: File.read!(@model),
      mapping: Mapping,
      ledger: context.ledger,
      to: to
    )
  end

  defp decision(verdict, applied) do
    %Decision{
      id: Id.new(),
      subject: %Subject{id: "ann", kind: :user},
      object: {:folder, 1},
      operation: :read,
      verdict: verdict,
      reason: Reason.allowed("can_read"),
      adapter: Turnstile.Fga,
      policy_version: "the model of another store",
      head_position: applied,
      applied_position: applied,
      operation_id: Id.new(),
      at: ~U[2026-09-09 12:00:00.000000Z]
    }
  end
end
