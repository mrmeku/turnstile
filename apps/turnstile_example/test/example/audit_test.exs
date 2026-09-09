defmodule Example.AuditTest do
  use Example.FakeCase, async: true

  alias Example.Audit
  alias Example.Audit.Chain
  alias Example.Audit.Record
  alias Example.Audit.Store
  alias Example.Documents
  alias Example.Fixture

  @now ~U[2026-09-08 12:00:00Z]

  test "a chain links each record to the previous digest from genesis and verifies" do
    chain = Chain.new()
    assert Chain.records(chain) == []
    assert Chain.verify(chain) == :ok

    chain =
      chain
      |> Chain.append(:decision, "op-1", %{verdict: "allow"}, @now)
      |> Chain.append(:override, nil, %{}, @now)

    assert [%Record{index: 0, previous: "genesis", hash: first}, %Record{index: 1, previous: second}] =
             Chain.records(chain)

    assert first == second

    assert Chain.verify(chain) == :ok
    [head | _rest] = Chain.records(chain)
    assert Record.digest(head) == first
  end

  test "a rewrite breaks the rewritten record and every one after it, and a rewrite to the same value breaks nothing" do
    chain = Enum.reduce(0..3, Chain.new(), &Chain.append(&2, :decision, "op-#{&1}", %{index: &1}, @now))
    assert {:error, [1, 2, 3]} = rewritten(chain, 1, &Map.put(&1, :index, 9))
    assert {:error, [3]} = rewritten(chain, 3, &Map.put(&1, :index, 9))
    assert :ok = rewritten(chain, 0, & &1)
  end

  test "an unattached store records what it is told and answers by operation id" do
    store = start_supervised!({Store, []})
    :ok = Store.record(store, :decision, "op-1", %{verdict: "allow"})
    :ok = Store.record(store, :override, "op-2", %{document_id: 1})
    :ok = Store.record(store, :decision, "op-1", %{verdict: "deny"})

    assert [%Record{kind: :decision, payload: %{verdict: "allow"}}, %Record{payload: %{verdict: "deny"}}] =
             Audit.records(store, "op-1")

    assert [%Record{kind: :override}] = Store.records(store, "op-2")
    assert Store.records(store, "op-3") == []
    assert Audit.verify(store) == :ok
    assert length(Chain.records(Store.chain(store))) == 3
  end

  test "an attached store records the port's decisions and the override event, keyed by operation id", ctx do
    store = start_supervised!({Store, [attach: true]})
    document = Fixture.document!(ctx.world)
    allow(ctx.rules, "ann", :read, {:document, document.id})
    ann = Fixture.subject("ann")
    gil = Fixture.subject("gil")
    {:ok, _document} = Documents.read(ann, document.id, operation_id: "op-read")
    {:error, _refusal} = Documents.read(Fixture.subject("bob"), document.id, operation_id: "op-deny")
    {:ok, _document} = Documents.override_read(gil, document.id, "why", operation_id: "op-override")
    assert Turnstile.check(ann, :read, Documents.object(document.id), operation_id: "op-check")
    _sync = Store.chain(store)
    assert [%Record{kind: :decision, payload: %{verdict: "allow", operation: "read"}}] = Store.records(store, "op-read")
    assert [%Record{kind: :decision, payload: %{verdict: "deny"}}] = Store.records(store, "op-deny")

    assert [%Record{kind: :override, payload: %{subject: %{id: "gil"}, document_id: id}}] =
             Store.records(store, "op-override")

    assert id == document.id
    assert [%Record{kind: :decision}] = Store.records(store, "op-check")
    assert Store.verify(store) == :ok

    assert Store.events() ==
             [[:example, :override, :read] | Enum.filter(Turnstile.Port.events(), &(List.last(&1) == :stop))]

    :ok = stop_supervised!(Store)
  end

  test "a stop span without a decision map records nothing" do
    store = start_supervised!({Store, []})
    :ok = Store.handle_event([:turnstile, :user, :stop], %{}, %{operation_id: "op-x"}, store)
    assert Store.records(store, "op-x") == []
  end

  defp rewritten(chain, index, fun) do
    chain
    |> Chain.rewrite(index, fun)
    |> Chain.verify()
  end
end
