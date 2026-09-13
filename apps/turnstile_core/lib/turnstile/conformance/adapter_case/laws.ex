defmodule Turnstile.Conformance.AdapterCase.Laws do
  @moduledoc """
  The bodies of the template's tests, each a function of the test context
  and the generated values, so the template stays a list of names and the
  assertions live where they can be read. Nothing here names a schema, a
  subject, or an operation: a law handed a population reaches its
  `Turnstile.Conformance.World` through the struct, and a law that needs a
  fixed one asks the module the template was given. Every writer of a
  population calls `tick/0` first, so the stubbed clock moves forward
  through a test and a replay at a time has one state to reproduce.
  """

  import Ecto.Query, only: [where: 2]
  import ExUnit.Assertions

  alias Turnstile.Conformance.World
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Ledger.Fold
  alias Turnstile.Object
  alias Turnstile.Projection.Drain
  alias Turnstile.Projection.Drift
  alias Turnstile.Schema
  alias Turnstile.Subject
  alias Turnstile.Test.Clock

  @base ~U[2026-01-01 00:00:00Z]
  @tick_key {__MODULE__, :tick}
  @rows 1_000

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
    Clock.set(DateTime.shift(@base, second: count))
  end

  @doc "Replace the tables' population with this one and seed the adapter."
  @spec populate(context(), World.t()) :: :ok
  def populate(%{repo: repo} = context, world) do
    module = World.module(world)
    tick()
    :ok = module.clear(repo)
    :ok = module.insert(repo, world)
    seed(context, world)
  end

  @doc "Seed the adapter with the population, through the template's `seed:` module when there is one."
  @spec seed(context(), World.t()) :: :ok
  def seed(%{case: %{seed: nil}}, _world), do: :ok
  def seed(%{case: %{seed: seed}}, world), do: seed.seed(world)

  @doc "The adapter answers `check` as the world's rule does."
  @spec rule_agreement(context(), World.t(), Subject.t(), atom(), Object.t()) :: true
  def rule_agreement(context, world, subject, operation, object) do
    populate(context, world)
    assert Turnstile.check(subject, operation, object) == World.module(world).allowed?(world, subject, operation, object)
  end

  @doc "For each protected schema, the rows the scope admits are the objects `check` allows; a denied scope admits none."
  @spec scope_fidelity(context(), World.t(), Subject.t(), atom()) :: :ok
  def scope_fidelity(%{repo: repo} = context, world, subject, operation) do
    module = World.module(world)
    populate(context, world)
    Enum.each(module.schemas(), &scope_of(repo, module, world, subject, operation, &1))
  end

  @doc "An unknown operation, a subject of an unknown kind, and a subject the population does not know are denied."
  @spec deny_by_default(
          context(),
          World.t(),
          %{subject: Subject.t(), stranger: Subject.t(), nobody: Subject.t()},
          atom(),
          Object.t()
        ) ::
          :ok
  def deny_by_default(context, world, %{subject: subject, stranger: stranger, nobody: nobody}, operation, object) do
    module = World.module(world)
    populate(context, world)
    known = hd(module.operations())
    denied_everywhere(subject, operation, object)
    denied_everywhere(stranger, known, object)
    denied_or_scoped_to_nothing(context, module, nobody, known, object)

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

  @doc "A grant written and taken away through the seam leaves two events, an empty fold, and a denial."
  @spec record_then_erase(context(), World.t(), Subject.t(), World.grantable(), atom()) :: true
  def record_then_erase(%{repo: repo} = context, world, subject, grantable, grant_type) do
    module = World.module(world)
    populate(context, world)
    world = module.revoke(repo, world, subject, grantable)
    :ok = seed(context, world)
    before = head(context)
    object = module.object_of(grantable)
    operation = hd(module.operations())

    granted = module.grant(repo, world, subject, grantable, grant_type)
    seed(context, granted)
    assert Turnstile.check(subject, operation, object) == module.allowed?(granted, subject, operation, object)

    revoked = module.revoke(repo, granted, subject, grantable)
    seed(context, revoked)
    assert_erased(events_after(context, before), subject, object, grant_type)
    assert Turnstile.check(subject, operation, object) == false
  end

  @doc "After a sequence of changes, the fold of the ledger equals the tables, and the fold at each time equals the state then."
  @spec fold_then_replay(context(), World.t(), [World.step()]) :: :ok
  def fold_then_replay(%{repo: repo} = context, world, steps) do
    module = World.module(world)
    populate(context, world)
    snapshots = snapshots(module, repo, world, steps)
    events = events_after(context, 0)
    folded = Fold.fold(events)
    assert folded.facts == module.facts(module.read(repo))
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
  def scoped_all_shape(context) do
    scoped_all_over_rows(context, &Turnstile.Test.with_config([ledger: :none], &1))
  end

  @doc "A single grant written in mode none: the write, no re-read, no ledger row."
  @spec fact_write_shape(context()) :: true
  def fact_write_shape(%{repo: repo, case: %{world: module}} = context) do
    world = module.ungranted()
    populate(context, world)
    before = head(context)
    {subject, grantable} = module.focus(world)
    grant_type = hd(module.grant_types())

    Turnstile.Test.with_config([ledger: :none], fn ->
      {_written, queries} =
        Turnstile.Test.queries(repo, fn -> module.insert_grant(repo, subject, grantable, grant_type) end)

      assert [insert] = queries
      assert insert =~ ~r/^INSERT/i
    end)

    assert head(context) == before
  end

  @doc "A scoped `all` over 1,000 rows under the ledger: the query and the adapter's own, one decision record, no ledger row."
  @spec scoped_all_ledger_shape(context()) :: true
  def scoped_all_ledger_shape(context), do: scoped_all_over_rows(context, & &1.())

  @doc "An adapter that requires a ledger refuses mode none, rather than answer from a projection nothing drains."
  @spec mode_none_refused(context()) :: true
  def mode_none_refused(%{case: %{adapter: adapter}}) do
    Turnstile.Test.with_config([ledger: :none], fn ->
      assert {:error, %Error.Unsupported{adapter: ^adapter, feature: :ledger_mode_none}} = Turnstile.Config.resolve()
    end)
  end

  @doc "With the engine unreachable, every call denies with `engine_unreachable` and no policy version."
  @spec fail_closed(context()) :: true
  def fail_closed(%{case: %{outage: outage, world: module}} = context) do
    {_world, subject, _grantable, object, operation} = granted_focus(context, module)

    :ok = outage.outage()
    assert Turnstile.check(subject, operation, object) == false
    assert Turnstile.batch(subject, operation, [object]) == %{Object.ref(object) => :deny}
    assert Turnstile.filter(subject, operation, [object]) == []

    assert {:error, %Error.NotAuthorized{reason: %{code: :engine_unreachable}}} =
             Turnstile.authorize(subject, operation, object)

    unreachable_scope(subject, operation, object.type)
  end

  @doc "The revocation-latency template: written to the log, never asserted."
  @spec latency(context()) :: :ok
  def latency(%{repo: repo, case: %{adapter: adapter, world: module}} = context) do
    {world, subject, grantable, object, operation} = granted_focus(context, module)

    started = System.monotonic_time(:millisecond)
    revoked = module.revoke(repo, world, subject, grantable)
    committed = System.monotonic_time(:millisecond)
    drain = drain_component(context)
    seed(context, revoked)
    polled = System.monotonic_time(:millisecond)
    assert Turnstile.Test.poll(fn -> not Turnstile.check(subject, operation, object) end)
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
  def projection_lag(%{case: %{projection: projector, world: module}, projection: projection} = context) do
    populate(context, module.layered())
    head = head(context)
    assert head > 0
    started = System.monotonic_time(:millisecond)
    assert {:ok, %Drain{from: 0, to: ^head}} = projector.drain_once(projection)
    finished = System.monotonic_time(:millisecond)
    assert {:ok, ^head} = projector.checkpoint(projection)
    report("projector_drain, #{inspect(projector)}: #{finished - started} ms to position #{head}\n")
  end

  @doc "A fact written into the state behind the projector's back is drift, and a rebuild is clean."
  @spec projection_drift(context()) :: true
  def projection_drift(%{case: %{projection: projector, world: module}, projection: projection} = context) do
    populate(context, module.layered())
    head = head(context)
    assert {:ok, %Drain{to: ^head}} = projector.drain_once(projection)
    assert {:ok, %Drift{missing: [], extra: [], checked_to: ^head}} = projector.reconcile(projection)
    :ok = projector.disturb(projection)
    assert {:ok, %Drift{checked_to: ^head} = drift} = projector.reconcile(projection)
    refute Drift.clean?(drift)
    assert {:ok, reference} = projector.rebuild(projection)
    assert is_binary(reference)
  end

  @doc "A drain that fails after applying part of its batch leaves the checkpoint; the next drain converges."
  @spec projection_convergence(context()) :: true
  def projection_convergence(%{case: %{projection: projector, world: module}, projection: projection} = context) do
    populate(context, module.layered())
    head = head(context)
    interrupted = projector.interrupt(projection)
    assert {:error, %Error.Engine{}} = projector.drain_once(interrupted)
    assert {:ok, 0} = projector.checkpoint(projection)
    assert {:ok, %Drain{from: 0, to: ^head}} = projector.drain_once(projection)
    assert {:ok, ^head} = projector.checkpoint(projection)
    assert {:ok, %Drift{} = drift} = projector.reconcile(projection)
    assert Drift.clean?(drift)
  end

  # The measurements are printed, never asserted, and the test logger sits
  # at warning, so they go to standard output as the template promises.
  # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
  defp report(text), do: IO.puts(text)

  defp allowed_ids(module, world, subject, operation) do
    type = Schema.object_type_of(module.scope_schema())

    for object <- module.objects(world),
        object.type == type,
        module.allowed?(world, subject, operation, object),
        do: object.id
  end

  defp scope_of(repo, module, world, subject, operation, schema) do
    type = Schema.object_type_of(schema)

    allowed =
      for object <- module.objects(world),
          object.type == type,
          Turnstile.check(subject, operation, object),
          do: object.id

    {rule, %Decision{} = decision} = Turnstile.scope(subject, operation, type)
    assert_scope(repo, module, where(schema, ^rule), decision, allowed)
  end

  defp assert_scope(repo, _module, query, %Decision{verdict: :scoped} = decision, allowed) do
    rows = repo.all(query, turnstile: decision)
    assert Enum.sort(Enum.map(rows, & &1.id)) == Enum.sort(allowed)
  end

  defp assert_scope(repo, module, query, %Decision{verdict: :deny} = decision, allowed) do
    assert allowed == []
    assert_raise Error.NotAuthorized, fn -> repo.all(query, turnstile: decision) end
    assert repo.all(query, turnstile: module.exemption()) == []
  end

  defp assert_erased(events, subject, object, grant_type) do
    assert [%{old: nil, new: ^grant_type}, %{old: ^grant_type, new: nil}] = events
    assert Enum.all?(events, &(&1.subject_ref == Subject.ref(subject) and &1.object_ref == Object.ref(object)))
    assert Enum.all?(events, &(&1.by == Subject.library() and &1.attribute == nil and &1.kind == :relationship))
    assert Fold.fold(events).facts == %{}
  end

  defp snapshots(module, repo, world, steps) do
    started = tick()

    {_final, snapshots} =
      Enum.reduce(steps, {world, [{started, module.facts(world)}]}, fn step, {current, snapshots} ->
        at = tick()
        next = module.apply_step(repo, current, step)
        {next, [{at, module.facts(next)} | snapshots]}
      end)

    snapshots
  end

  # The two shape laws over a filled table differ in the ledger mode the
  # scoped read runs under and in nothing else, so the population, the count,
  # and the three assertions are written once. The population itself is
  # written under the configured mode in both, since a mode the law is not
  # about is no part of what it counts.
  defp scoped_all_over_rows(%{repo: repo, case: %{world: module}} = context, run) do
    world = module.scoped()
    populate(context, world)
    :ok = module.fill(repo, world, @rows)
    before = head(context)
    {subject, _grantable} = module.focus(world)
    operation = hd(module.operations())
    run.(fn -> scoped_all_counted(context, world, subject, operation) end)
    assert head(context) == before
  end

  defp scoped_all_counted(%{repo: repo, case: %{setup_queries: queries_added, world: module}}, world, subject, operation) do
    {rows, queries, decisions} = scoped_all(module, repo, subject, operation)
    expected = 1 + queries_added

    assert Enum.sort(Enum.map(rows, & &1.id)) == allowed_ids(module, world, subject, operation)
    assert length(queries) == expected, "expected #{expected} queries, got #{inspect(queries)}"
    assert decisions == 1
  end

  # The scope of an unreachable engine denies, and names no policy version,
  # since there was none to read.
  defp unreachable_scope(subject, operation, type) do
    {_rule, %Decision{} = decision} = Turnstile.scope(subject, operation, type)
    assert decision.verdict == :deny
    assert decision.reason.code == :engine_unreachable
    assert decision.policy_version == nil
  end

  # What a law that takes a grant away starts from: one grant in force, the
  # subject and the object it is over, and an operation it allows.
  defp granted_focus(context, module) do
    world = module.granted()
    populate(context, world)
    {subject, grantable} = module.focus(world)
    object = module.object_of(grantable)
    operation = hd(module.operations())
    assert Turnstile.check(subject, operation, object)
    {world, subject, grantable, object, operation}
  end

  defp scoped_all(module, repo, subject, operation) do
    schema = module.scope_schema()
    type = Schema.object_type_of(schema)
    handler = :telemetry_test.attach_event_handlers(self(), Turnstile.Port.events())

    {rows, queries} =
      Turnstile.Test.queries(repo, fn ->
        {rule, decision} = Turnstile.scope(subject, operation, type)
        repo.all(where(schema, ^rule), turnstile: decision)
      end)

    :telemetry.detach(handler)
    {rows, queries, decisions(handler)}
  end

  defp drain_component(%{case: %{projection: nil}}), do: "not measured"

  defp drain_component(%{case: %{projection: projector}, projection: projection}) do
    started = System.monotonic_time(:millisecond)
    assert {:ok, %Drain{}} = projector.drain_once(projection)
    "#{System.monotonic_time(:millisecond) - started} ms"
  end

  defp denied_everywhere(subject, operation, object) do
    denied(subject, operation, object)
    {_rule, %Decision{verdict: verdict}} = Turnstile.scope(subject, operation, object.type)
    assert verdict == :deny
  end

  # A subject the population does not know is denied per object; its scope is
  # denied, or narrows to no row, since an adapter whose rule is a query
  # learns who the subject is when the query runs.
  defp denied_or_scoped_to_nothing(%{repo: repo}, module, subject, operation, object) do
    denied(subject, operation, object)
    schema = Enum.find(module.schemas(), &(Schema.object_type_of(&1) == object.type))
    {rule, %Decision{} = decision} = Turnstile.scope(subject, operation, object.type)
    assert_scope(repo, module, where(schema, ^rule), decision, [])
  end

  defp denied(subject, operation, object) do
    assert Turnstile.check(subject, operation, object) == false
    assert {:error, %Error.NotAuthorized{}} = Turnstile.authorize(subject, operation, object)
    assert Turnstile.batch(subject, operation, [object]) == %{Object.ref(object) => :deny}
    assert Turnstile.filter(subject, operation, [object]) == []
  end

  defp verdict(true), do: :allow
  defp verdict(false), do: :deny

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
