defmodule Example.Scenarios.Audit do
  @moduledoc "The decision-audit, access-review, and change-control scenarios that need no ledger."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, Turnstile, Turnstile.Test, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Audit.Chain
  alias Example.Fixture
  alias Turnstile.Id
  alias Turnstile.PolicyVersion

  @stop [:turnstile, :user, :stop]

  @spec aud_01() :: term()
  def aud_01 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    _ref = :telemetry_test.attach_event_handlers(self(), [@stop])
    assert_read(subject("ann"), document, operation_id: operation_id)
    assert [decision] = decisions(operation_id)
    assert decision.subject == %{id: "ann", kind: "user", session_id: nil}
    assert decision.object == {"document", document.id}
    assert decision.operation == "read"
    assert decision.verdict == "allow"
    assert decision.operation_id == operation_id
    assert_record_fields(decision)
  end

  @spec aud_02() :: term()
  def aud_02 do
    world = Fixture.world!()
    document = Fixture.document!(world)
    operation_id = Id.new()
    _ref = :telemetry_test.attach_event_handlers(self(), [@stop])
    assert_denied(subject("frank"), document, operation_id: operation_id)
    assert [decision] = decisions(operation_id)
    assert decision.verdict == "deny"
    assert %{code: code, message: message} = decision.reason
    assert code != "" and message != ""
  end

  @spec aud_03() :: term()
  def aud_03 do
    world = Fixture.world!()
    document = Fixture.document!(world, controls: [:federal_only, :no_foreign], releasable_to: ["GB"], list: ["ann"])
    operation_id = Id.new()
    _ref = :telemetry_test.attach_event_handlers(self(), [@stop])
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
    now = DateTime.utc_now()

    chain =
      Enum.reduce(0..4, Chain.new(), fn index, chain ->
        Chain.append(chain, :decision, "op-#{index}", %{verdict: "allow", index: index}, now)
      end)

    assert :ok = Chain.verify(chain)
    assert length(Chain.records(chain)) == 5
    rewritten = Chain.rewrite(chain, 2, &Map.put(&1, :verdict, "deny"))
    assert {:error, [2, 3, 4]} = Chain.verify(rewritten)
    assert :ok = Chain.verify(Chain.rewrite(chain, 2, & &1))
  end

  @spec rvw_01() :: term()
  def rvw_01 do
    world = Fixture.world!()
    open = Fixture.document!(world)
    federal = Fixture.document!(world, controls: [:federal_only])
    foreign = Fixture.document!(world, program: world.foreign_program, office: world.foreign_office)
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

    try do
      assert_version_fields(version)
      assert_denied_under(version, document)
    after
      :ok = rules.restore()
    end
  end

  defp assert_record_fields(decision) do
    assert %{code: code, message: message} = decision.reason
    assert is_binary(code) and is_binary(message)
    assert is_binary(decision.policy_version)
    assert Map.has_key?(decision, :head_position) and Map.has_key?(decision, :applied_position)
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
    _ref = :telemetry_test.attach_event_handlers(self(), [@stop])
    assert Turnstile.Test.poll(fn -> not reads?(subject("ann"), document) end)
    assert_denied(subject("ann"), document, operation_id: operation_id)
    assert [%{policy_version: recorded}] = decisions(operation_id)
    assert recorded == expected
  end

  defp decisions(operation_id) do
    receive do
      {@stop, _ref, _measurements, %{operation_id: ^operation_id, decision: decision}} ->
        [decision | decisions(operation_id)]

      {@stop, _ref, _measurements, _metadata} ->
        decisions(operation_id)
    after
      0 -> []
    end
  end
end
