defmodule Turnstile.Conformance.AdapterCase.Laws do
  @moduledoc """
  The bodies of the template's tests, each a function of the test context
  and the generated values, so the template stays a list of names and the
  assertions live where they can be read. Every writer of a world calls
  `tick/0` first, so the stubbed clock moves forward through a test and a
  replay at a time has one state to reproduce.
  """

  import Ecto.Query, only: [where: 2]
  import ExUnit.Assertions

  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Fixture.World
  alias Turnstile.Ledger.Fold
  alias Turnstile.Object
  alias Turnstile.Projection.Drain
  alias Turnstile.Projection.Drift
  alias Turnstile.Schema
  alias Turnstile.Subject

  @base ~U[2026-01-01 00:00:00Z]
  @tick_key {__MODULE__, :tick}
  @schemas [Folder, Item]

  @typedoc "The test context the template's setup builds."
  @type context :: %{
          required(:repo) => module(),
          required(:ledger) => {module(), keyword()} | :none,
          required(:case) => map(),
          optional(atom()) => term()
        }

  @doc "Advance the stubbed clock one second and return the new time."
  @spec tick() :: DateTime.t()
  def tick do
    count = Process.get(@tick_key, 0) + 1
    Process.put(@tick_key, count)
    at = DateTime.shift(@base, second: count)
    Mox.stub(Turnstile.Test.Clock.Mock, :now, fn -> at end)
    at
  end

  @doc "Replace the tables' population with the world and seed the adapter."
  @spec populate(context(), World.t()) :: :ok
  def populate(%{repo: repo} = context, %World{} = world) do
    tick()
    :ok = World.clear(repo)
    :ok = World.insert(repo, world)
    seed(context, world)
  end

  @doc "Seed the adapter with the world, through the template's `seed:` module when there is one."
  @spec seed(context(), World.t()) :: :ok
  def seed(%{case: %{seed: nil}}, %World{}), do: :ok
  def seed(%{case: %{seed: seed}}, %World{} = world), do: seed.seed(world)

  @doc "The adapter answers `check` as the world's rule does."
  @spec rule_agreement(context(), World.t(), Subject.t(), atom(), Object.t()) :: true
  def rule_agreement(context, world, subject, operation, object) do
    populate(context, world)
    assert Turnstile.check(subject, operation, object) == World.allowed?(world, subject.id, operation, object)
  end

  @doc "For each object type, the rows the scope admits are the objects `check` allows; a denied scope admits none."
  @spec scope_fidelity(context(), World.t(), Subject.t(), atom()) :: :ok
  def scope_fidelity(%{repo: repo} = context, world, subject, operation) do
    populate(context, world)
    Enum.each(@schemas, &scope_of(repo, world, subject, operation, &1))
  end

  @doc "An unknown operation, a subject of an unknown kind, and a subject the world does not know are denied everywhere."
  @spec deny_by_default(
          context(),
          World.t(),
          %{subject: Subject.t(), stranger: Subject.t(), nobody: Subject.t()},
          atom(),
          Object.t()
        ) ::
          :ok
  def deny_by_default(context, world, %{subject: subject, stranger: stranger, nobody: nobody}, operation, object) do
    populate(context, world)
    known = hd(World.operations())
    denied_everywhere(subject, operation, object)
    denied_everywhere(stranger, known, object)
    denied_or_scoped_to_nothing(context, nobody, known, object)

    assert {:error, %Error.NotAuthorized{reason: %{code: :unknown_subject_kind}}} =
             Turnstile.authorize(stranger, known, object)
  end

  @doc "`batch` and `filter` agree with `check`, object by object."
  @spec batch_agreement(context(), World.t(), Subject.t(), atom(), [Object.t()]) :: true
  def batch_agreement(context, world, subject, operation, objects) do
    populate(context, world)
    verdicts = Map.new(objects, &{Object.ref(&1), verdict(Turnstile.check(subject, operation, &1))})
    assert Turnstile.batch(subject, operation, objects) == verdicts
    assert Turnstile.filter(subject, operation, objects) == Enum.filter(objects, &Turnstile.check(subject, operation, &1))
  end

  @doc "A membership written and deleted through the seam leaves two events, an empty fold, and a denial."
  @spec record_then_erase(context(), World.t(), String.t(), pos_integer(), :reader | :editor) :: true
  def record_then_erase(%{repo: repo} = context, world, account, folder, role) do
    world = %{world | memberships: Map.delete(world.memberships, {account, folder})}
    populate(context, world)
    before = head(context)
    subject = %Subject{id: account, kind: :user}
    object = %Object{type: :folder, id: folder}

    granted = World.grant(repo, world, account, folder, role)
    seed(context, granted)
    assert Turnstile.check(subject, :read, object) == World.allowed?(granted, account, :read, object)

    revoked = World.revoke(repo, granted, account, folder)
    seed(context, revoked)
    assert_erased(events_after(context, before), subject, object, role)
    assert Turnstile.check(subject, :read, object) == false
  end

  @doc "After a sequence of changes, the fold of the ledger equals the tables, and the fold at each time equals the state then."
  @spec fold_then_replay(context(), World.t(), [Turnstile.Conformance.Gen.step()]) :: :ok
  def fold_then_replay(%{repo: repo} = context, world, steps) do
    populate(context, world)
    snapshots = snapshots(repo, world, steps)
    events = events_after(context, 0)
    folded = Fold.fold(events)
    assert folded.facts == World.facts(World.read(repo))
    assert folded.position == head(context)
    Enum.each(snapshots, fn {at, facts} -> assert Fold.at(events, at).facts == facts end)
  end

  @doc "`from_map` of `to_map` is the struct."
  @spec round_trip(module(), struct()) :: true
  def round_trip(module, %{} = struct) do
    assert module.from_map(module.to_map(struct)) == {:ok, struct}
  end

  @doc "A scoped `all` over 1,000 rows in mode none: one query plus the adapter's, one decision record, no ledger row."
  @spec scoped_all_shape(context()) :: true
  def scoped_all_shape(%{repo: repo, case: %{setup_queries: setup_queries}} = context) do
    populate(context, %{world_of_one() | folders: [1, 2, 3]})
    :ok = insert_folders(repo, 4..1_000)
    before = head(context)

    Turnstile.Test.with_config([ledger: :none], fn ->
      {folders, queries, decisions} = scoped_all(repo, %Subject{id: "acct-a", kind: :user})
      assert Enum.map(folders, & &1.id) == [1]
      assert length(queries) == 1 + setup_queries, "expected #{1 + setup_queries} queries, got #{inspect(queries)}"
      assert decisions == 1
    end)

    assert head(context) == before
  end

  @doc "A single-row fact write in mode none: the write, no re-read, no ledger row."
  @spec fact_write_shape(context()) :: true
  def fact_write_shape(%{repo: repo} = context) do
    populate(context, %{world_of_one() | memberships: %{}})
    before = head(context)

    Turnstile.Test.with_config([ledger: :none], fn ->
      {_membership, queries} =
        Turnstile.Test.queries(repo, fn ->
          repo.insert!(%Membership{account_id: "acct-a", folder_id: 1, role: :reader}, turnstile: World.exemption())
        end)

      assert [insert] = queries
      assert insert =~ ~r/^INSERT/i
    end)

    assert head(context) == before
  end

  @doc "A scoped `all` over 1,000 rows under the ledger: the query and the adapter's own, one decision record, no ledger row."
  @spec scoped_all_ledger_shape(context()) :: true
  def scoped_all_ledger_shape(%{repo: repo, case: %{setup_queries: setup_queries}} = context) do
    populate(context, %{world_of_one() | folders: [1, 2, 3]})
    :ok = insert_folders(repo, 4..1_000)
    before = head(context)
    {folders, queries, decisions} = scoped_all(repo, %Subject{id: "acct-a", kind: :user})

    assert Enum.map(folders, & &1.id) == [1]
    assert length(queries) == 1 + setup_queries, "expected #{1 + setup_queries} queries, got #{inspect(queries)}"
    assert decisions == 1
    assert head(context) == before
  end

  @doc "An adapter that requires a ledger refuses mode none, rather than answer from a projection nothing drains."
  @spec mode_none_refused(context()) :: true
  def mode_none_refused(%{case: %{adapter: adapter}}) do
    Turnstile.Test.with_config([ledger: :none], fn ->
      assert {:error, %Error.Unsupported{adapter: ^adapter, feature: :ledger_mode_none}} = Turnstile.Config.resolve()
    end)
  end

  @doc "With the engine unreachable, every call denies with `engine_unreachable` and no policy version."
  @spec fail_closed(context()) :: true
  def fail_closed(%{case: %{outage: outage}} = context) do
    populate(context, world_of_one())
    subject = %Subject{id: "acct-a", kind: :user}
    object = %Object{type: :folder, id: 1}
    assert Turnstile.check(subject, :read, object)

    :ok = outage.outage()
    assert Turnstile.check(subject, :read, object) == false

    assert {:error, %Error.NotAuthorized{reason: %{code: :engine_unreachable}}} =
             Turnstile.authorize(subject, :read, object)

    assert Turnstile.batch(subject, :read, [object]) == %{{:folder, 1} => :deny}
    assert Turnstile.filter(subject, :read, [object]) == []
    {_rule, %Decision{} = decision} = Turnstile.scope(subject, :read, :folder)
    assert decision.verdict == :deny
    assert decision.reason.code == :engine_unreachable
    assert decision.policy_version == nil
  end

  @doc "The revocation-latency template: written to the log, never asserted."
  @spec latency(context()) :: :ok
  def latency(%{repo: repo, case: %{adapter: adapter}} = context) do
    world = world_of_one()
    populate(context, world)
    subject = %Subject{id: "acct-a", kind: :user}
    object = %Object{type: :folder, id: 1}
    assert Turnstile.check(subject, :read, object)

    started = System.monotonic_time(:millisecond)
    revoked = World.revoke(repo, world, "acct-a", 1)
    committed = System.monotonic_time(:millisecond)
    drain = drain_component(context)
    seed(context, revoked)
    polled = System.monotonic_time(:millisecond)
    assert Turnstile.Test.poll(fn -> not Turnstile.check(subject, :read, object) end)
    finished = System.monotonic_time(:millisecond)

    report("""
    revocation latency, #{inspect(adapter)}: total #{finished - started} ms
      commit #{committed - started} ms
      projector_drain #{drain}
      poll #{finished - polled} ms, floor #{Turnstile.Test.poll_interval()} ms
      replica_lag not measured
      cache not measured
    """)
  end

  @doc "One drain from a fresh checkpoint covers the head; its duration is printed as `projector_drain`."
  @spec projection_lag(context()) :: :ok
  def projection_lag(%{case: %{projection: module}, projection: projection} = context) do
    populate(context, world_of_three())
    head = head(context)
    assert head > 0
    started = System.monotonic_time(:millisecond)
    assert {:ok, %Drain{from: 0, to: ^head}} = module.drain_once(projection)
    finished = System.monotonic_time(:millisecond)
    assert {:ok, ^head} = module.checkpoint(projection)
    report("projector_drain, #{inspect(module)}: #{finished - started} ms to position #{head}\n")
  end

  @doc "A fact written into the state behind the projector's back is drift, and a rebuild is clean."
  @spec projection_drift(context()) :: true
  def projection_drift(%{case: %{projection: module}, projection: projection} = context) do
    populate(context, world_of_three())
    head = head(context)
    assert {:ok, %Drain{to: ^head}} = module.drain_once(projection)
    assert {:ok, %Drift{missing: [], extra: [], checked_to: ^head}} = module.reconcile(projection)
    :ok = module.disturb(projection)
    assert {:ok, %Drift{checked_to: ^head} = drift} = module.reconcile(projection)
    refute Drift.clean?(drift)
    assert {:ok, reference} = module.rebuild(projection)
    assert is_binary(reference)
  end

  @doc "A drain that fails after applying part of its batch leaves the checkpoint; the next drain converges."
  @spec projection_convergence(context()) :: true
  def projection_convergence(%{case: %{projection: module}, projection: projection} = context) do
    populate(context, world_of_three())
    head = head(context)
    interrupted = module.interrupt(projection)
    assert {:error, %Error.Engine{}} = module.drain_once(interrupted)
    assert {:ok, 0} = module.checkpoint(projection)
    assert {:ok, %Drain{from: 0, to: ^head}} = module.drain_once(projection)
    assert {:ok, ^head} = module.checkpoint(projection)
    assert {:ok, %Drift{} = drift} = module.reconcile(projection)
    assert Drift.clean?(drift)
  end

  defp world_of_one do
    %World{accounts: %{"acct-a" => World.cleared()}, folders: [1], memberships: %{{"acct-a", 1} => :editor}}
  end

  defp world_of_three do
    %World{
      accounts: %{"acct-a" => World.cleared(), "acct-b" => World.cleared()},
      folders: [1, 2],
      items: %{1 => 1},
      memberships: %{{"acct-a", 1} => :editor, {"acct-b", 2} => :reader, {"acct-a", 2} => :reader}
    }
  end

  # The measurements are printed, never asserted, and the test logger sits
  # at warning, so they go to standard output as the template promises.
  # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
  defp report(text), do: IO.puts(text)

  defp scope_of(repo, world, subject, operation, schema) do
    type = Schema.object_type_of(schema)

    allowed =
      for object <- World.objects(world),
          object.type == type,
          Turnstile.check(subject, operation, object),
          do: object.id

    {rule, %Decision{} = decision} = Turnstile.scope(subject, operation, type)
    assert_scope(repo, where(schema, ^rule), decision, allowed)
  end

  defp assert_scope(repo, query, %Decision{verdict: :scoped} = decision, allowed) do
    rows = repo.all(query, turnstile: decision)
    assert Enum.sort(Enum.map(rows, & &1.id)) == Enum.sort(allowed)
  end

  defp assert_scope(repo, query, %Decision{verdict: :deny} = decision, allowed) do
    assert allowed == []
    assert_raise Error.NotAuthorized, fn -> repo.all(query, turnstile: decision) end
    assert repo.all(query, turnstile: World.exemption()) == []
  end

  defp assert_erased(events, subject, object, role) do
    assert [%{old: nil, new: ^role}, %{old: ^role, new: nil}] = events
    assert Enum.all?(events, &(&1.subject_ref == Subject.ref(subject) and &1.object_ref == Object.ref(object)))
    assert Enum.all?(events, &(&1.by == Subject.library() and &1.attribute == nil and &1.kind == :relationship))
    assert Fold.fold(events).facts == %{}
  end

  defp snapshots(repo, world, steps) do
    started = tick()

    {_final, snapshots} =
      Enum.reduce(steps, {world, [{started, World.facts(world)}]}, fn step, {current, snapshots} ->
        at = tick()
        next = apply_step(repo, current, step)
        {next, [{at, World.facts(next)} | snapshots]}
      end)

    snapshots
  end

  defp insert_folders(repo, ids) do
    rows = for id <- ids, do: %{id: id, name: "folder #{id}"}
    {count, nil} = repo.insert_all(Folder, rows, turnstile: World.exemption())
    assert count == Range.size(ids)
    :ok
  end

  defp scoped_all(repo, subject) do
    handler = :telemetry_test.attach_event_handlers(self(), Turnstile.Port.events())

    {folders, queries} =
      Turnstile.Test.queries(repo, fn ->
        {rule, decision} = Turnstile.scope(subject, :read, :folder)
        repo.all(where(Folder, ^rule), turnstile: decision)
      end)

    :telemetry.detach(handler)
    {folders, queries, decisions(handler)}
  end

  defp drain_component(%{case: %{projection: nil}}), do: "not measured"

  defp drain_component(%{case: %{projection: module}, projection: projection}) do
    started = System.monotonic_time(:millisecond)
    assert {:ok, %Drain{}} = module.drain_once(projection)
    "#{System.monotonic_time(:millisecond) - started} ms"
  end

  defp denied_everywhere(subject, operation, object) do
    denied(subject, operation, object)
    {_rule, %Decision{verdict: verdict}} = Turnstile.scope(subject, operation, object.type)
    assert verdict == :deny
  end

  # A subject the world does not know is denied per object; its scope is
  # denied, or narrows to no row, since an adapter whose rule is a query
  # learns who the subject is when the query runs.
  defp denied_or_scoped_to_nothing(%{repo: repo}, subject, operation, object) do
    denied(subject, operation, object)
    schema = Enum.find(@schemas, &(Schema.object_type_of(&1) == object.type))
    {rule, %Decision{} = decision} = Turnstile.scope(subject, operation, object.type)
    assert_scope(repo, where(schema, ^rule), decision, [])
  end

  defp denied(subject, operation, object) do
    assert Turnstile.check(subject, operation, object) == false
    assert {:error, %Error.NotAuthorized{}} = Turnstile.authorize(subject, operation, object)
    assert Turnstile.batch(subject, operation, [object]) == %{Object.ref(object) => :deny}
    assert Turnstile.filter(subject, operation, [object]) == []
  end

  defp verdict(true), do: :allow
  defp verdict(false), do: :deny

  defp apply_step(repo, world, {:grant, account, folder, role}), do: World.grant(repo, world, account, folder, role)
  defp apply_step(repo, world, {:revoke, account, folder}), do: World.revoke(repo, world, account, folder)
  defp apply_step(repo, world, {:clearance, account, value}), do: World.set_clearance(repo, world, account, value)

  defp head(%{ledger: :none}), do: nil

  defp head(%{ledger: {module, options}}) do
    {:ok, head} = module.head(options)
    head
  end

  defp events_after(%{ledger: {module, options}}, position) do
    {:ok, events} = module.read(options, position, 1_000_000)
    events
  end

  defp decisions(handler) do
    receive do
      {[:turnstile, _kind, :stop], ^handler, _measurements, %{decision: %{}}} -> 1 + decisions(handler)
    after
      0 -> 0
    end
  end
end
