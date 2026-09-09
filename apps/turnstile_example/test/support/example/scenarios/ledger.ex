defmodule Example.Scenarios.Ledger do
  @moduledoc """
  The scenarios marked `ledger` in the reference's table: the ones whose
  answer is in the record of what changed rather than in the tables. They
  run only when the boot configuration names a ledger, and they read it
  through the ledger that configuration names, so they say nothing about
  which adapter is bound.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios.Support,
      ExUnit,
      Turnstile,
      Turnstile.Facts,
      Turnstile.Ledger.Reader,
      Turnstile.Ledger.Reconcile,
      Turnstile.Ledger.Reconcile.Scheduler,
      Turnstile.Ledger.Replay,
      Turnstile.Test
    ]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Accounts
  alias Example.Assignment
  alias Example.Document
  alias Example.Documents
  alias Example.Fixture
  alias Example.Program
  alias Example.Repo
  alias Example.Review
  alias Turnstile.FactEvent
  alias Turnstile.Facts
  alias Turnstile.Id
  alias Turnstile.Ledger.Fold
  alias Turnstile.Ledger.Reader
  alias Turnstile.Ledger.Reconcile
  alias Turnstile.Ledger.Reconcile.Scheduler
  alias Turnstile.Ledger.Replay
  alias Turnstile.PolicyVersion
  alias Turnstile.Projection.Drift

  @bulk_stop [:turnstile, :bulk, :stop]
  @bulk_start [:turnstile, :bulk, :start]
  @bulk_exception [:turnstile, :bulk, :exception]
  @reconcile [:turnstile, :ledger, :reconcile]
  @user_stop [:turnstile, :user, :stop]

  @spec rev_07() :: term()
  def rev_07 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert_read(subject("ann"), document)
    assert 1 = Accounts.unassign("ann", world.program.id)
    assert_denied(subject("ann"), document)

    assert %Document{} = Repo.get(Document, document.id, turnstile: Fixture.exemption())
    assert %Program{} = Repo.get(Program, world.program.id, turnstile: Fixture.exemption())

    grant = membership("ann", world.program)
    assert Enum.map(about(grant), &{&1.old, &1.new}) == [{nil, :member}, {:member, nil}]
  end

  @spec aud_04() :: term()
  def aud_04 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    :ok = watch_decisions()
    marking = %{categories: ["PRVCY"], controls: [:federal_only]}
    options = [operation_id: operation_id] ++ fresh()

    assert {:ok, _marking} = Documents.change_marking(subject("dana"), document.id, marking, options)
    assert [decision] = decisions(operation_id)
    assert decision.operation == "change_marking"
    assert_marking_events(under(operation_id), document)
  end

  @spec aud_05() :: term()
  def aud_05 do
    world = Fixture.world!()
    documents = for title <- ~w[one two three], do: Fixture.document!(world, title: title)
    _ref = :telemetry_test.attach_event_handlers(self(), Facts.events())

    assert {:ok, record} = Documents.decontrol_all(subject("dana"), DateTime.utc_now(), fresh())
    assert {record.operation, record.schema, record.count} == {:update, Document, 3}
    assert_receive {@bulk_stop, _ref, _measurements, %{record: ^record}}
    assert_decontrol_events(under(record.operation_id), documents, record)
  end

  @spec aud_06() :: term()
  def aud_06 do
    world = Fixture.world!()
    grant = membership("frank", world.program)

    assert %Assignment{} = Accounts.assign("frank", world.program.id, :member)
    assert [granted] = about(grant)
    assert {granted.kind, granted.attribute, granted.old, granted.new} == {:relationship, nil, nil, :member}

    assert 1 = Accounts.unassign("frank", world.program.id)
    assert [^granted, revoked] = about(grant)
    assert {revoked.kind, revoked.attribute, revoked.old, revoked.new} == {:relationship, nil, :member, nil}
    assert revoked.position > granted.position
  end

  @spec aud_08() :: term()
  def aud_08 do
    world = Fixture.world!()
    _document = Fixture.document!(world)
    recorded = events()
    :ok = watch_decisions()
    _ref = :telemetry_test.attach_event_handlers(self(), Facts.events())

    assert_raise Postgrex.Error, fn -> Accounts.assign_all(["frank"], -1, :member) end

    assert_receive {@bulk_start, _start_ref, _started, %{operation: :insert}}
    assert_receive {@bulk_exception, _exception_ref, _exception, %{operation: :insert}}
    refute_received {@bulk_stop, _stop_ref, _stopped, _stop_metadata}
    refute_received {@user_stop, _user_ref, _user, _user_metadata}
    assert events() == recorded
  end

  @spec rvw_02() :: term()
  def rvw_02 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert document.id in reads_of("ann", world.agency)
    assignments = Reconcile.facts(options(), [Assignment])
    at = DateTime.utc_now()

    assert 1 = Accounts.unassign("ann", world.program.id)
    refute document.id in reads_of("ann", world.agency)
    refute Map.has_key?(Reconcile.facts(options(), [Assignment]), membership("ann", world.program))
    assert_folds_to(at, assignments)
    assert_reviews_as_folded(at)
  end

  @spec rvw_03(module()) :: term()
  def rvw_03(rules) do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    :ok = watch_decisions()
    assert_read(subject("ann"), document, operation_id: operation_id)
    assert [decision] = decisions(operation_id)
    grant = membership("ann", world.program)
    replay = assert_replays(decision, grant)

    assert 1 = Accounts.unassign("ann", world.program.id)
    again = assert_replays(decision, grant)
    assert again.fold.facts == replay.fold.facts
    assert_reproduces(rules, again, decision, document)
  end

  @spec rvw_04() :: term()
  def rvw_04 do
    world = Fixture.world!()
    assert {:ok, %Drift{} = clean} = Reconcile.run(options(), Example.schemas())
    assert Drift.clean?(clean), "the ledger and the tables differ before the write outside the seam: #{inspect(clean)}"

    :ok = outside_the_seam("frank", world.program)
    _ref = :telemetry_test.attach_event_handlers(self(), [Scheduler.event()])
    scheduler = start_scheduler(interval: 100, first: 0)

    try do
      assert_receive {@reconcile, _ref, %{extra: 1}, %{drift: %Drift{} = drift, clean?: false}}, 2_000
      assert drift.extra == [{membership("frank", world.program), :member}]
      assert drift.missing == []
    after
      :ok = GenServer.stop(scheduler)
    end
  end

  @spec cm_01(module()) :: term()
  def cm_01(rules) do
    assert {:ok, %PolicyVersion{} = version} = rules.publish_tightened()

    try do
      published = for %FactEvent{kind: :policy_version} = event <- events(), do: event.new
      assert Enum.any?(published, &(&1.version == version.version))
      assert length(published) >= 2
      for published_version <- published, do: assert_attributed(published_version)
    after
      :ok = rules.restore()
    end
  end

  @spec cm_02(module()) :: term()
  def cm_02(rules) do
    world = Fixture.world!()
    document = Fixture.document!(world)
    under_n = Id.new()
    :ok = watch_decisions()
    assert_read(subject("ann"), document, operation_id: under_n)
    assert [made_under_n] = decisions(under_n)

    assert {:ok, %PolicyVersion{} = next} = rules.publish_tightened()

    try do
      assert [published] = for(event <- events(), current?(event, next), do: event)
      assert published.old == made_under_n.policy_version
      recorded = denied_under(document)
      assert recorded == next.version
      assert recorded != made_under_n.policy_version
    after
      :ok = rules.restore()
    end
  end

  defp assert_marking_events(written, document) do
    assert Enum.map(written, &{&1.attribute, &1.old, &1.new}) == [
             {:categories, nil, "PRVCY"},
             {:controls, nil, :federal_only}
           ]

    assert Enum.map(written, & &1.object_ref) == [{:document, document.id}, {:document, document.id}]
    assert Enum.map(written, & &1.position) == consecutive(written)
  end

  defp assert_decontrol_events(written, documents, record) do
    assert Enum.map(written, & &1.attribute) == [:decontrol, :decontrol, :decontrol]
    assert Enum.map(written, & &1.object_ref) == for(document <- documents, do: {:document, document.id})
    assert {record.min_position, record.max_position} == {hd(written).position, List.last(written).position}
  end

  # The rows the reporter answers for a past date, against the grants the
  # fold holds there: the review of a date is the fold stopped at it.
  defp assert_reviews_as_folded(at) do
    date = DateTime.to_date(at)
    assert {:ok, replay} = Replay.at(ledger(), DateTime.new!(date, ~T[23:59:59.999999]))
    rows = Review.rows(at: date)
    assert rows != []
    assert Enum.map(rows, &{&1.subject, &1.object, &1.operation}) == Enum.sort(granted(replay))
  end

  defp granted(replay) do
    for {{{:user, id}, {type, object_id}, nil}, role} <- replay.fold.facts, role, do: {id, "#{type}:#{object_id}", role}
  end

  # The fold of the ledger as it stood at that moment, over the facts the
  # tables held then.
  defp assert_folds_to(at, facts) do
    assert {:ok, replay} = Replay.at(ledger(), at)
    assert Replay.positioned?(replay)
    assert Map.take(replay.fold.facts, Map.keys(facts)) == facts
  end

  # The ledger as it stood when the decision was made, which holds the grant
  # the decision rested on and the version it was made under, however the
  # tables have moved since.
  defp assert_replays(decision, grant) do
    assert {:ok, replay} = Replay.to(ledger(), decision.applied_position, adapter: adapter())
    assert Replay.positioned?(replay)
    assert replay.fold.facts[grant] == :member
    assert replay.policy_version.version == decision.policy_version
    replay
  end

  # The verdict the record holds, asked again with the state and the
  # policies the replay names in force: the same answer, whatever the tables
  # hold now. What putting those two back costs is the binding's, and
  # `Example.Scenarios.Rules` is where a test asks for it.
  defp assert_reproduces(rules, replay, decision, document) do
    assert decision.verdict == "allow"
    refute reads?(subject("ann"), document)
    assert rules.replay(replay, fn -> reads?(subject("ann"), document) end)
  end

  defp assert_attributed(%PolicyVersion{author: author, approval: approval}) do
    assert is_binary(author) and author != ""
    assert is_binary(approval) and approval != ""
  end

  # The version the port records once the tightened policy has reached it.
  defp denied_under(document) do
    operation_id = Id.new()
    assert Turnstile.Test.poll(fn -> not reads?(subject("ann"), document) end)
    assert_denied(subject("ann"), document, operation_id: operation_id)
    assert [decision] = decisions(operation_id)
    decision.policy_version
  end

  # The readers of one account, as the review reports them.
  defp reads_of(account, agency), do: Review.readers(subject("eve"), agency, fresh())[subject(account)]

  # An INSERT that never passes the seam, through the owner-role repo: what
  # a patch applied by hand looks like to the ledger.
  defp outside_the_seam(user_id, %Program{id: program_id}) do
    sql = "INSERT INTO assignments (user_id, program_id, role) VALUES ($1, $2, $3)"
    _result = Example.OwnerRepo.query!(sql, [user_id, program_id, "member"])
    :ok
  end

  defp start_scheduler(options) do
    {:ok, scheduler} =
      Scheduler.start_link(Keyword.merge([ledger: options(), schemas: Example.schemas()], options))

    scheduler
  end

  defp current?(%FactEvent{kind: :policy_version, new: %PolicyVersion{version: version}}, %PolicyVersion{version: version}) do
    true
  end

  defp current?(%FactEvent{}, %PolicyVersion{}), do: false

  defp membership(user_id, %Program{id: program_id}), do: {{:user, user_id}, {:program, program_id}, nil}

  defp about(key), do: for(event <- events(), Fold.key(event) == key, do: event)

  defp under(operation_id), do: for(event <- events(), event.operation_id == operation_id, do: event)

  defp consecutive(events), do: Enum.to_list(hd(events).position..(hd(events).position + length(events) - 1))

  defp events do
    {:ok, events} = Reader.all(ledger())
    events
  end

  defp ledger do
    {:ok, config} = Turnstile.Config.resolve()
    config.ledger
  end

  defp options do
    {_module, options} = ledger()
    options
  end
end
