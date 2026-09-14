defmodule Example.Scenarios.Audit do
  @moduledoc "The decision-audit, access-review, and change-control scenarios."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, Turnstile, Turnstile.Test, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Accounts
  alias Example.Assignment
  alias Example.Documents
  alias Example.Fixture
  alias Example.Marking
  alias Example.Program
  alias Example.Repo
  alias Example.Siem
  alias Turnstile.Answer
  alias Turnstile.Id
  alias Turnstile.PolicyVersion

  @spec aud_01() :: term()
  def aud_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    :ok = watch_decisions()

    settle()
    assert_read(subject("ann"), document, operation_id: operation_id)
    assert [decision] = decisions(operation_id)
    assert decision.subject == subject("ann")
    assert decision.subject_kind == :user
    assert decision.object == {:document, document.id}
    assert decision.operation == :read
    assert decision.verdict == :allow
    assert decision.operation_id == operation_id
    assert_record_fields(decision)
  end

  @spec aud_02() :: term()
  def aud_02 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    :ok = watch_decisions()

    settle()
    assert_denied(subject("frank"), document, operation_id: operation_id)
    assert [decision] = decisions(operation_id)
    assert decision.verdict == :deny
    assert decision.reason in (Answer.reasons() -- [:allowed])
  end

  @spec aud_03() :: term()
  def aud_03 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only, :no_foreign], releasable_to: ["GB"], list: ["ann"])
    operation_id = Id.new()
    :ok = watch_decisions()

    settle()
    assert_read(subject("ann"), document, operation_id: operation_id)
    assert_denied(subject("bob"), document, operation_id: operation_id)
    assert_denied(subject("carl"), document, operation_id: operation_id)

    records =
      operation_id
      |> decisions()
      |> inspect(limit: :infinity, printable_limit: :infinity)

    for value <- ["federal", "contractor", "\"US\"", "\"FR\"", "\"GB\"", "no_foreign", "federal_only", "named_list"] do
      refute records =~ value, "the decision record carries the attribute value #{value}"
    end
  end

  @spec aud_04() :: term()
  def aud_04 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    :ok = watch_decisions()

    settle()
    {_result, changes} = Turnstile.Test.changes(fn -> assert_marking_changed(document, operation_id) end)

    assert [decision] = decisions(operation_id)
    assert decision.operation == :change_marking
    assert [%{operation: :update, target: {:marking, _id}} = change] = banners(changes)
    assert change.operation_id == operation_id
    assert change.changes == %{categories: {[], ["PRVCY"]}, controls: {[], [:federal_only]}}
  end

  @spec aud_05() :: term()
  def aud_05 do
    world = Fixture.world!()
    documents = for title <- ~w[one two three], do: Fixture.document!(world, title: title)

    settle()

    {error, changes} =
      Turnstile.Test.changes(fn ->
        assert_raise Turnstile.Error, fn ->
          Repo.update_all(Marking, [set: [controls: [:federal_only]]], turnstile: Fixture.exemption())
        end
      end)

    assert Exception.message(error) =~ "bulk write to an audited schema"
    assert changes == []
    assert Enum.map(markings(documents), & &1.controls) == [[], [], []]
  end

  @spec aud_06() :: term()
  def aud_06 do
    world = Fixture.world!()

    {granted, grant} = Turnstile.Test.changes(fn -> Accounts.assign("frank", world.program.id, :member) end)
    assert %Assignment{} = granted
    assert [%{operation: :create, changes: %{role: {nil, :member}}} = created] = grant
    assert created.target == {:assignment, granted.id}

    {removed, revoke} = Turnstile.Test.changes(fn -> Accounts.unassign("frank", world.program.id) end)
    assert removed == 1
    assert [%{operation: :delete, changes: %{role: {:member, nil}}} = deleted] = revoke
    assert deleted.target == created.target
  end

  @spec aud_07() :: term()
  def aud_07 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    {:ok, siem} = Siem.start_link(attach: true)

    try do
      settle()
      assert_marking_changed(document, operation_id)
      assert_mapped(Siem.records(siem, operation_id))
    after
      :ok = GenServer.stop(siem)
    end
  end

  @spec aud_08() :: term()
  def aud_08 do
    world = Fixture.world!()
    granted = assignments()

    {_raised, changes} =
      Turnstile.Test.changes(fn ->
        assert_raise Ecto.ConstraintError, fn -> Accounts.assign_all(["frank"], world.program.id + 10_000, :member) end
      end)

    assert changes == []
    assert assignments() == granted
  end

  @spec rvw_01() :: term()
  def rvw_01 do
    world = Fixture.world!()
    open = Fixture.document!(world)
    federal = Fixture.document!(world, controls: [:federal_only])
    foreign = Fixture.document!(world, program: world.foreign_program, office: world.foreign_office)

    settle()
    report = Example.Review.report(subject("eve"), fresh())
    [_head, domestic, foreign_section] = String.split(report, ~r/^agency /m)
    assert_section(domestic, "Domestic", ann: [open, federal], bob: [open], frank: [], ivan: [])
    assert_section(foreign_section, "Foreign", ivan: [foreign], ann: [])
    readers = Example.Review.readers(subject("eve"), world.agency, fresh())
    assert readers[subject("ann")] == [open.id, federal.id]
    assert readers[subject("bob")] == [open.id]
  end

  @spec rvw_04() :: term()
  def rvw_04 do
    world = Fixture.world!()

    {:ok, changes} = Turnstile.Test.changes(fn -> outside_the_seam("frank", world.program) end)

    assert changes == []
    assert Enum.any?(assignments(), &(&1.user_id == "frank"))
  end

  @spec cm_01(module()) :: term()
  def cm_01(rules) do
    event = rules.version_event()
    ref = :telemetry_test.attach_event_handlers(self(), [event])

    try do
      assert {:ok, %PolicyVersion{} = version} = rules.publish_tightened()
      assert_receive {^event, ^ref, _measurements, %{version: ^version}}
      assert_version_fields(version)
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

    settle()
    assert_read(subject("ann"), document, operation_id: under_n)
    assert [made_under_n] = decisions(under_n)

    assert {:ok, %PolicyVersion{} = next} = rules.publish_tightened()

    try do
      assert next.version != made_under_n.version
      assert_denied_under(next, document)
    after
      :ok = rules.restore()
    end
  end

  @spec cm_03(module()) :: term()
  def cm_03(rules) do
    world = Fixture.world!()
    document = Fixture.document!(world)
    :ok = watch_decisions()
    assert {:ok, %PolicyVersion{} = version} = rules.publish_tightened()

    settle()

    try do
      assert_version_fields(version)
      assert_denied_under(version, document)
    after
      :ok = rules.restore()
    end
  end

  # The change events about a banner, which is the row a marking change
  # writes the fields of; the document it hangs from is written too, and
  # what that write changed is nothing.
  defp banners(changes), do: for(%{schema: Marking} = change <- changes, do: change)

  # An INSERT that never passes the seam, through the owner-role repo: what
  # a patch applied by hand looks like to a record built from change events.
  defp outside_the_seam(user_id, %Program{id: program_id}) do
    sql = "INSERT INTO assignments (user_id, program_id, role) VALUES ($1, $2, $3)"
    _result = Example.OwnerRepo.query!(sql, [user_id, program_id, "member"])
    :ok
  end

  # The assignments the tables hold, in the order their ids were granted.
  defp assignments, do: Enum.sort_by(Repo.all(Assignment, turnstile: Fixture.exemption()), & &1.id)

  # Each document's banner as the tables hold it now.
  defp markings(documents) do
    for document <- documents do
      assert {:ok, read} = Documents.fetch(document.id, Fixture.exemption())
      read.marking
    end
  end

  defp assert_marking_changed(document, operation_id) do
    marking = %{categories: ["PRVCY"], controls: [:federal_only]}
    options = [operation_id: operation_id] ++ fresh()

    assert {:ok, _marking} = Documents.change_marking(subject("dana"), document.id, marking, options)
  end

  defp assert_mapped([decision | changes]) do
    assert {decision.class_uid, decision.status} == {6003, "Success"}
    assert decision.api.operation == "change_marking"
    assert Enum.any?(changes, &(&1.entity.type == "marking" and &1.activity_name == "Update"))
    for record <- [decision | changes], do: assert_ocsf_fields(record)
  end

  # Every record names the schema version it was mapped against, and its
  # type identifier is the class and the activity, which is how OCSF
  # builds it.
  defp assert_ocsf_fields(record) do
    assert record.metadata.version == Siem.schema_version()
    assert record.type_uid == record.class_uid * 100 + record.activity_id
  end

  # The reason a record carries is one word every decider shares.
  defp assert_record_fields(decision) do
    assert decision.reason in Answer.reasons()
    assert is_binary(decision.version)
    assert decision.decider == adapter()
    assert %DateTime{} = decision.time
  end

  defp assert_section(section, agency, reads) do
    assert section =~ agency

    for {account, documents} <- reads do
      assert section =~ "#{account} reads [#{Enum.map_join(documents, ", ", & &1.id)}]"
    end
  end

  defp assert_version_fields(%PolicyVersion{} = version) do
    for field <- [:version, :content_hash, :author, :approval] do
      value = Map.fetch!(version, field)
      assert is_binary(value) and value != "", "policy version #{field} is empty"
    end

    assert is_binary(version.content) or is_binary(version.pointer)
  end

  defp assert_denied_under(%PolicyVersion{version: expected}, document) do
    operation_id = Id.new()
    assert Turnstile.Test.poll(fn -> not reads?(subject("ann"), document) end, propagation_deadline())
    assert_denied(subject("ann"), document, operation_id: operation_id)
    assert [%{version: recorded}] = decisions(operation_id)
    assert recorded == expected
  end
end
