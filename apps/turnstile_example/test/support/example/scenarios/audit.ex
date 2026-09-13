defmodule Example.Scenarios.Audit do
  @moduledoc "The decision-audit, access-review, and change-control scenarios that need no ledger."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, Turnstile, Turnstile.Test, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Documents
  alias Example.Fixture
  alias Example.Siem
  alias Example.Siem.Ocsf
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

  @spec cm_03(module()) :: term()
  def cm_03(rules) do
    world = Fixture.world!()
    document = Fixture.document!(world)
    assert {:ok, %PolicyVersion{} = version} = rules.publish_tightened()

    settle()

    try do
      assert_version_fields(version)
      assert_denied_under(version, document)
    after
      :ok = rules.restore()
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
    assert record.metadata.version == Ocsf.version()
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
    :ok = watch_decisions()
    assert Turnstile.Test.poll(fn -> not reads?(subject("ann"), document) end, propagation_deadline())
    assert_denied(subject("ann"), document, operation_id: operation_id)
    assert [%{version: recorded}] = decisions(operation_id)
    assert recorded == expected
  end
end
