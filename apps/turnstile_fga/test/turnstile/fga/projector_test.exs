defmodule Turnstile.Fga.ProjectorTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Fga.Checkpoint
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Probe
  alias Turnstile.Fga.Projector
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fixture.World
  alias Turnstile.Projection.Drain
  alias Turnstile.Projection.Drift
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "conformance")
    ledger = Probe.ledger()
    {:ok, projector} = projector(agent, store, ledger, [])

    {:ok, agent: agent, store: store, ledger: ledger, projector: projector}
  end

  defp projector(agent, store, ledger, options) do
    defaults = [
      client: Fake,
      endpoint: agent,
      store: store,
      store_name: "rebuilt",
      model: %{"schema_version" => "1.1"},
      mapping: Mapping,
      ledger: ledger,
      repo: Sandboxed
    ]

    Projector.new(Keyword.merge(defaults, options))
  end

  defp condition(nil), do: nil
  defp condition(value), do: %Condition{name: "while_cleared", context: %{"clearance" => value}}

  defp reader(clearance) do
    %TupleKey{user: "user:ann", relation: "reader", object: "folder:1", condition: condition(clearance)}
  end

  defp member(clearance), do: %TupleKey{user: "user:ann", relation: "member", object: "clearance:#{clearance}"}

  # A membership and a clearance: the folder tuple carries the clearance, so
  # the two objects the drain touches are the folder and the clearance.
  defp granted_and_cleared(context) do
    Probe.append(context.ledger, [Probe.granted("ann", 1, :reader), Probe.clearance("ann", nil, World.cleared())])
  end

  test "a store no checkpoint row names stands at zero", context do
    assert Projector.checkpoint(context.projector) == {:ok, 0}
  end

  test "a drain over a ledger with nothing in it applies nothing and writes nothing", context do
    assert Projector.drain_once(context.projector) == {:ok, %Drain{from: 0, to: 0, applied: 0}}
    assert Fake.writes(context.agent) == []
  end

  test "the first drain writes the tuples the fold requires and advances the checkpoint", context do
    _events = granted_and_cleared(context)

    assert Projector.drain_once(context.projector) == {:ok, %Drain{from: 0, to: 2, applied: 2}}
    assert Fake.tuples(context.agent, context.store) == [member(World.cleared()), reader(World.cleared())]
    assert Projector.checkpoint(context.projector) == {:ok, 2}
  end

  test "a drain over events already applied writes nothing", context do
    _events = granted_and_cleared(context)
    assert {:ok, %Drain{applied: 2}} = Projector.drain_once(context.projector)

    assert Projector.drain_once(context.projector) == {:ok, %Drain{from: 2, to: 2, applied: 0}}
    assert length(Fake.writes(context.agent)) == 2
  end

  test "a drain interrupted after one write leaves an exact checkpoint, and the next drain converges", context do
    _events = granted_and_cleared(context)
    :ok = Fake.fail_after(context.agent, 1)

    assert {:error, %Error.Engine{operation: :write}} = Projector.drain_once(context.projector)
    assert Projector.checkpoint(context.projector) == {:ok, 1}
    assert Fake.tuples(context.agent, context.store) == [reader(World.cleared())]

    :ok = Fake.fail_after(context.agent, nil)
    assert {:ok, %Drain{from: 1, to: 2, applied: 1}} = Projector.drain_once(context.projector)
    assert Fake.tuples(context.agent, context.store) == [member(World.cleared()), reader(World.cleared())]
    assert Projector.checkpoint(context.projector) == {:ok, 2}
  end

  test "a clearance that changed is a delete and a write of the same tuple key, in two calls", context do
    _events = granted_and_cleared(context)
    assert {:ok, %Drain{applied: 2}} = Projector.drain_once(context.projector)
    _changed = Probe.append(context.ledger, [Probe.clearance("ann", World.cleared(), "secret")])

    assert {:ok, %Drain{from: 2, to: 3, applied: 1}} = Projector.drain_once(context.projector)

    assert [%Write{deletes: [deleted], writes: []}, %Write{deletes: [], writes: [written]}] =
             Enum.take(Fake.writes(context.agent), -2)

    assert TupleKey.key(deleted) == TupleKey.key(written)
    assert deleted == reader(World.cleared())
    assert written == reader("secret")
    assert Fake.tuples(context.agent, context.store) == [member("secret"), reader("secret")]
    assert Projector.checkpoint(context.projector) == {:ok, 3}
  end

  test "the checkpoint stands below an event whose tuple is deleted and not written again yet", context do
    _events = granted_and_cleared(context)
    assert {:ok, %Drain{applied: 2}} = Projector.drain_once(context.projector)
    _changed = Probe.append(context.ledger, [Probe.clearance("ann", World.cleared(), "secret")])
    :ok = Fake.fail_after(context.agent, 3)

    assert {:error, %Error.Engine{operation: :write}} = Projector.drain_once(context.projector)
    assert Projector.checkpoint(context.projector) == {:ok, 2}
    assert Fake.tuples(context.agent, context.store) == [member("secret")]

    :ok = Fake.fail_after(context.agent, nil)
    assert {:ok, %Drain{from: 2, to: 3, applied: 1}} = Projector.drain_once(context.projector)
    assert Fake.tuples(context.agent, context.store) == [member("secret"), reader("secret")]
  end

  test "a role that changed is one call carrying a delete and a write", context do
    _events = granted_and_cleared(context)
    assert {:ok, %Drain{applied: 2}} = Projector.drain_once(context.projector)
    _changed = Probe.append(context.ledger, [Probe.changed("ann", 1, :reader, :editor)])

    assert {:ok, %Drain{from: 2, to: 3, applied: 1}} = Projector.drain_once(context.projector)

    assert [%Write{deletes: [deleted], writes: [written]}] = Enum.take(Fake.writes(context.agent), -1)
    assert deleted.relation == "reader"
    assert written.relation == "editor"
    assert Projector.checkpoint(context.projector) == {:ok, 3}
  end

  test "a difference larger than one call is split, and the checkpoint waits for the last of them", context do
    {:ok, projector} = projector(context.agent, context.store, context.ledger, batch: 2)
    cleared = for account <- ["ann", "bob", "cid"], do: Probe.clearance(account, nil, World.cleared())
    grants = for account <- ["ann", "bob", "cid"], do: Probe.granted(account, 1, :reader)
    _events = Probe.append(context.ledger, cleared ++ grants)
    :ok = Fake.fail_after(context.agent, 1)

    assert {:error, %Error.Engine{operation: :write}} = Projector.drain_once(projector)

    assert [%Write{deletes: [], writes: [_first, _second]}, %Write{deletes: [], writes: [_third]}] =
             Fake.writes(context.agent)

    assert length(Fake.tuples(context.agent, context.store)) == 2
    assert Projector.checkpoint(projector) == {:ok, 0}

    :ok = Fake.fail_after(context.agent, nil)
    assert {:ok, %Drain{from: 0, to: 6, applied: 6}} = Projector.drain_once(projector)
    assert length(Fake.tuples(context.agent, context.store)) == 6
    assert Projector.checkpoint(projector) == {:ok, 6}
  end

  test "a published version applies and advances the checkpoint with no write", context do
    _events = Probe.append(context.ledger, [Probe.published("model-1")])

    assert Projector.drain_once(context.projector) == {:ok, %Drain{from: 0, to: 1, applied: 1}}
    assert Fake.writes(context.agent) == []
    assert Projector.checkpoint(context.projector) == {:ok, 1}
  end

  test "reconcile answers no drift over a store the drain has just written", context do
    _events = granted_and_cleared(context)
    assert {:ok, %Drain{applied: 2}} = Projector.drain_once(context.projector)

    assert {:ok, %Drift{} = drift} = Projector.reconcile(context.projector)
    assert Drift.clean?(drift)
    assert drift.checked_to == 2
  end

  test "reconcile finds a tuple the store lacks and one it holds beside the fold", context do
    _events = granted_and_cleared(context)
    assert {:ok, %Drain{applied: 2}} = Projector.drain_once(context.projector)
    stray = %TupleKey{user: "user:zed", relation: "reader", object: "folder:1"}
    change = %Write{deletes: [reader(World.cleared())], writes: [stray]}
    assert {:ok, 2} = Fake.write(context.agent, context.store, change)

    assert {:ok, %Drift{} = drift} = Projector.reconcile(context.projector)
    refute Drift.clean?(drift)
    assert drift.missing == [reader(World.cleared())]
    assert drift.extra == [stray]
  end

  test "rebuild creates a store, publishes the model, and folds into it from position zero", context do
    _events = granted_and_cleared(context)

    assert {:ok, rebuilt} = Projector.rebuild(context.projector)
    assert rebuilt != context.store
    assert Fake.tuples(context.agent, rebuilt) == [member(World.cleared()), reader(World.cleared())]
    assert {:write_model, %{"schema_version" => "1.1"}} in Fake.calls(context.agent)
    assert Checkpoint.position(Sandboxed, rebuilt) == 2
    assert Projector.checkpoint(context.projector) == {:ok, 0}
  end

  test "a read the client refuses fails the drain", context do
    {:ok, projector} = projector(context.agent, "store-404", context.ledger, [])
    _events = granted_and_cleared(context)

    assert {:error, %Error.Engine{operation: :read}} = Projector.drain_once(projector)
  end

  test "configuration that does not validate is an invalid error, and the schema is the projector's", context do
    assert {:error, %Error.Invalid{what: :projector, detail: detail}} =
             projector(context.agent, context.store, context.ledger, batch: 0)

    assert detail =~ "batch"
    assert %NimbleOptions{} = Projector.options_schema()
  end
end
