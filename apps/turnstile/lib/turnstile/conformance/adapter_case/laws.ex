defmodule Turnstile.Conformance.AdapterCase.Laws do
  @moduledoc """
  The bodies of the template's tests, each a function of the test context
  and the generated values, so the template stays a list of names and the
  assertions live where they can be read. Nothing here names a schema, a
  subject, or an operation: a law handed a population reaches its
  `Turnstile.Conformance.World` through the struct, and a law that needs a
  fixed one asks the module the template was given. Every writer of a
  population calls `tick/0` first, so the stubbed clock moves forward
  through a test and two writes never share a moment.

  This module carries the access-control laws (`ac3`), the revocation
  latency (`ac2-05`), the fact-write shape, and what every law body shares:
  writing a population, the granted focus, and reading the decision events
  a call published. The account laws are in `Laws.Accounts`, the audit laws
  in `Laws.Audit`, and the change-management laws in `Laws.Versions`.
  """

  import Ecto.Query, only: [where: 2]
  import ExUnit.Assertions

  alias Turnstile.Conformance.World
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Schema
  alias Turnstile.Test.Clock

  @base ~U[2026-01-01 00:00:00Z]
  @tick_key {__MODULE__, :tick}
  @rows 1_000

  @typedoc "The test context the template's setup builds."
  @type context :: %{required(:repo) => module(), required(:case) => map(), optional(atom()) => term()}

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

  @doc "`ac3-01`: the adapter answers `check` as the world's rule does."
  @spec rule_agreement(context(), World.t(), Turnstile.subject(), atom(), Turnstile.object()) :: true
  def rule_agreement(context, world, subject, operation, object) do
    populate(context, world)
    module = World.module(world)
    assert Turnstile.check(subject, operation, object) == module.allowed?(world, subject, operation, object)
  end

  @doc """
  `ac3-03`: for each protected schema, the rows the scope admits are the
  objects `check` allows; a denied scope admits none.
  """
  @spec scope_fidelity(context(), World.t(), Turnstile.subject(), atom()) :: :ok
  def scope_fidelity(%{repo: repo} = context, world, subject, operation) do
    module = World.module(world)
    populate(context, world)
    Enum.each(module.schemas(), &scope_of(repo, module, world, subject, operation, &1))
  end

  @doc """
  `ac3-02`: every object the rule does not grant the subject, an unknown
  operation, a subject of an unknown kind, and a subject the population does
  not know are denied, the unknown kind before the adapter is asked.
  """
  @spec deny_by_default(
          context(),
          World.t(),
          %{subject: Turnstile.subject(), stranger: Turnstile.subject(), nobody: Turnstile.subject()},
          atom(),
          Turnstile.object()
        ) ::
          :ok
  def deny_by_default(context, world, %{subject: subject, stranger: stranger, nobody: nobody}, operation, object) do
    module = World.module(world)
    populate(context, world)
    known = hd(module.operations())
    Enum.each(ungranted(module, world, subject, known), &denied(subject, known, &1))
    denied_everywhere(subject, operation, object)
    denied_everywhere(stranger, known, object)
    denied_or_scoped_to_nothing(context, module, nobody, known, object)

    assert {:error, %Error{reason: :unknown_subject_kind}} =
             Turnstile.authorize(stranger, known, object)
  end

  @doc "`ac3-04`: a scoped `all` over 1,000 rows is one query plus the adapter's own, and one decision record."
  @spec scoped_all_shape(context()) :: true
  def scoped_all_shape(%{repo: repo, case: %{world: module}} = context) do
    world = module.scoped()
    populate(context, world)
    :ok = module.fill(repo, world, @rows)
    {subject, _grantable} = module.focus(world)

    scoped_all_counted(context, world, subject, hd(module.operations()))
  end

  @doc "A single grant written through the seam: the write and nothing beside it."
  @spec fact_write_shape(context()) :: true
  def fact_write_shape(%{repo: repo, case: %{world: module}} = context) do
    world = module.ungranted()
    populate(context, world)
    {subject, grantable} = module.focus(world)

    {_granted, queries} =
      Turnstile.Test.queries(repo, fn -> module.insert_grant(repo, world, subject, grantable, []) end)

    assert [insert] = queries
    assert insert =~ ~r/^INSERT/i
  end

  @doc """
  `ac3-05`: with the engine unreachable, every call denies with
  `engine_unreachable` and no policy version, and each publishes one
  decision event carrying what broke.
  """
  @spec fail_closed(context()) :: :ok
  def fail_closed(%{case: %{outage: outage, world: module}} = context) do
    {_world, subject, _grantable, object, operation} = granted_focus(context, module)

    :ok = outage.outage()
    handler = :telemetry_test.attach_event_handlers(self(), [Turnstile.Port.event()])
    assert Turnstile.check(subject, operation, object) == false

    assert {:error, %Error{reason: :engine_unreachable}} =
             Turnstile.authorize(subject, operation, object)

    unreachable_scope(subject, operation, elem(object, 0))
    :telemetry.detach(handler)

    events = decision_events(handler)
    assert length(events) == 3
    Enum.each(events, &assert_closed/1)
  end

  @doc "`ac2-05`: after a revocation the next check denies; the latency is written to the log, never asserted."
  @spec latency(context()) :: :ok
  def latency(%{repo: repo, case: %{adapter: adapter, world: module}} = context) do
    {world, subject, grantable, object, operation} = granted_focus(context, module)

    started = System.monotonic_time(:millisecond)
    revoked = module.revoke(repo, world, subject, grantable)
    committed = System.monotonic_time(:millisecond)
    drain = drain_component(context, revoked)
    polled = System.monotonic_time(:millisecond)
    assert Turnstile.Test.poll(fn -> not Turnstile.check(subject, operation, object) end)
    finished = System.monotonic_time(:millisecond)

    report("""
    revocation latency, #{inspect(adapter)}: total #{finished - started} ms
      commit #{committed - started} ms
      settle #{drain}
      poll #{finished - polled} ms, floor #{Turnstile.Test.poll_interval()} ms
      replica_lag not measured
      cache not measured
    """)
  end

  @doc """
  Print a measurement. The measurements are printed, never asserted, and
  the test logger sits at warning, so they go to standard output as the
  template promises.
  """
  @spec report(String.t()) :: :ok
  # credo:disable-for-next-line Credo.Check.Refactor.IoPuts
  def report(text) when is_binary(text), do: IO.puts(text)

  @doc """
  What a law that takes a grant away starts from: the granted world
  written, the user it grants to, the grantable, the object it is over,
  and an operation it allows, with the grant checked to be in force.
  """
  @spec granted_focus(context(), module()) ::
          {World.t(), Turnstile.subject(), World.grantable(), Turnstile.object(), atom()}
  def granted_focus(context, module) do
    world = module.granted()
    populate(context, world)
    {subject, grantable} = module.focus(world)
    object = module.object_of(grantable)
    operation = hd(module.operations())
    assert Turnstile.check(subject, operation, object)
    {world, subject, grantable, object, operation}
  end

  @doc "The subject is denied the operation on the object by `check` and by `authorize`, with a reason and a detail."
  @spec denied(Turnstile.subject(), atom(), Turnstile.object()) :: true
  def denied(subject, operation, object) do
    assert Turnstile.check(subject, operation, object) == false
    assert {:error, %Error{reason: reason, detail: detail}} = Turnstile.authorize(subject, operation, object)
    assert reason in Error.reasons()
    assert detail =~ "may not #{operation}"
  end

  @doc """
  The rows the query admits under the decision are exactly the ids allowed:
  a scoped decision reads them, and a denied decision admits none, refuses
  the read, and leaves the table readable under the world's exemption.
  """
  @spec assert_scope(module(), module(), Ecto.Queryable.t(), Decision.t(), [term()]) :: true
  def assert_scope(repo, _module, query, %Decision{verdict: :scoped} = decision, allowed) do
    rows = repo.all(query, turnstile: decision)
    assert Enum.sort(Enum.map(rows, & &1.id)) == Enum.sort(allowed)
  end

  def assert_scope(repo, module, query, %Decision{verdict: :deny} = decision, allowed) do
    assert allowed == []
    assert_raise Error, ~r/may not/, fn -> repo.all(query, turnstile: decision) end
    assert repo.all(query, turnstile: module.exemption()) == []
  end

  @doc "The function's result, and the decision events it published, in order."
  @spec recorded((-> result)) :: {result, [map()]} when result: term()
  def recorded(fun) when is_function(fun, 0) do
    handler = :telemetry_test.attach_event_handlers(self(), [Turnstile.Port.event()])

    try do
      {fun.(), decision_events(handler)}
    after
      :telemetry.detach(handler)
    end
  end

  @doc """
  The decision events this process received on the handler, in order,
  leaving out the one a call that raised published with no verdict.
  """
  @spec decision_events(reference()) :: [map()]
  def decision_events(handler) do
    receive do
      {[:turnstile, :decision], ^handler, _measurements, %{verdict: nil}} ->
        decision_events(handler)

      {[:turnstile, :decision], ^handler, _measurements, metadata} ->
        [metadata | decision_events(handler)]
    after
      0 -> []
    end
  end

  defp allowed_ids(module, world, subject, operation) do
    type = Schema.object_type_of(module.scope_schema())

    for {object_type, id} = object <- module.objects(world),
        object_type == type,
        module.allowed?(world, subject, operation, object),
        do: id
  end

  defp scope_of(repo, module, world, subject, operation, schema) do
    type = Schema.object_type_of(schema)

    allowed =
      for {object_type, id} = object <- module.objects(world),
          object_type == type,
          Turnstile.check(subject, operation, object),
          do: id

    {rule, %Decision{} = decision} = Turnstile.scope(subject, operation, type)
    assert_scope(repo, module, where(schema, ^rule), decision, allowed)
  end

  defp scoped_all_counted(context, world, subject, operation) do
    %{repo: repo, case: %{setup_queries: queries_added, world: module}} = context
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
    assert decision.reason == :engine_unreachable
    assert decision.policy_version == nil
  end

  defp scoped_all(module, repo, subject, operation) do
    schema = module.scope_schema()
    type = Schema.object_type_of(schema)
    handler = :telemetry_test.attach_event_handlers(self(), [Turnstile.Port.event()])

    {rows, queries} =
      Turnstile.Test.queries(repo, fn ->
        {rule, decision} = Turnstile.scope(subject, operation, type)
        repo.all(where(schema, ^rule), turnstile: decision)
      end)

    :telemetry.detach(handler)
    {rows, queries, length(decision_events(handler))}
  end

  # What brings the adapter's own state into step after the revocation, and
  # how long it took. An adapter reading the application's own tables seeds
  # nothing and has nothing to measure here.
  defp drain_component(%{case: %{seed: nil}}, _world), do: "not measured"

  defp drain_component(context, world) do
    started = System.monotonic_time(:millisecond)
    :ok = seed(context, world)
    "#{System.monotonic_time(:millisecond) - started} ms"
  end

  defp denied_everywhere(subject, operation, {type, _id} = object) do
    denied(subject, operation, object)
    {_rule, %Decision{verdict: verdict}} = Turnstile.scope(subject, operation, type)
    assert verdict == :deny
  end

  # A subject the population does not know is denied per object; its scope is
  # denied, or narrows to no row, since an adapter whose rule is a query
  # learns who the subject is when the query runs.
  defp denied_or_scoped_to_nothing(%{repo: repo}, module, subject, operation, {type, _id} = object) do
    denied(subject, operation, object)
    schema = Enum.find(module.schemas(), &(Schema.object_type_of(&1) == type))
    {rule, %Decision{} = decision} = Turnstile.scope(subject, operation, type)
    assert_scope(repo, module, where(schema, ^rule), decision, [])
  end

  # The objects the rule grants the subject nothing on, under the operation.
  defp ungranted(module, world, subject, operation) do
    Enum.reject(module.objects(world), &module.allowed?(world, subject, operation, &1))
  end

  # A decision the outage closed: denied, for the engine being out of reach,
  # with what broke on the event.
  defp assert_closed(event) do
    assert event.verdict == :deny
    assert event.reason == :engine_unreachable
    assert is_exception(event.exception), "the closed decision carries no exception: #{inspect(event.exception)}"
  end
end
