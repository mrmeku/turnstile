defmodule Turnstile.Fga.Client.FakeTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.BatchCheck
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.Expand
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Tree
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.TupleKey

  setup do
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "conformance")

    {:ok, agent: agent, store: store}
  end

  defp tuple(user, relation, object, condition \\ nil) do
    %TupleKey{user: user, relation: relation, object: object, condition: condition}
  end

  defp write!(context, deletes, writes) do
    Fake.write(context.agent, context.store, %Write{deletes: deletes, writes: writes})
  end

  test "a store is created under an id of its own and a model is published into it", context do
    assert {:ok, other} = Fake.create_store(context.agent, "another")
    assert other != context.store

    assert {:ok, "model-1"} = Fake.write_model(context.agent, context.store, %{"schema_version" => "1.1"})
    assert {:ok, "model-2"} = Fake.write_model(context.agent, context.store, %{"schema_version" => "1.1"})
  end

  test "a call against a store that is not there is an engine error naming the call", context do
    assert {:error, %Error.Engine{adapter: Turnstile.Fga, operation: :write_model}} =
             Fake.write_model(context.agent, "store-404", %{})

    assert {:error, %Error.Engine{operation: :read}} =
             Fake.read(context.agent, "store-404", %Read{object_type: "folder"})

    assert {:error, %Error.Engine{operation: :write}} =
             Fake.write(context.agent, "store-404", %Write{deletes: [], writes: []})
  end

  test "a write puts its tuples in the store and answers how many changes it carried", context do
    reader = tuple("user:ann", "reader", "folder:1")
    member = tuple("user:ann", "member", "clearance:cleared")

    assert write!(context, [], [reader, member]) == {:ok, 2}
    assert Fake.tuples(context.agent, context.store) == [member, reader]
    assert write!(context, [member], []) == {:ok, 1}
    assert Fake.tuples(context.agent, context.store) == [reader]
  end

  test "a duplicate write is refused and the call changes nothing", context do
    reader = tuple("user:ann", "reader", "folder:1")
    assert write!(context, [], [reader]) == {:ok, 1}

    assert {:error, %Error.Engine{operation: :write, detail: detail}} =
             write!(context, [], [tuple("user:ann", "editor", "folder:1"), reader])

    assert detail =~ "user:ann reader folder:1"
    assert Fake.tuples(context.agent, context.store) == [reader]
  end

  test "a delete of a tuple the store does not hold is refused and the call changes nothing", context do
    reader = tuple("user:ann", "reader", "folder:1")
    assert write!(context, [], [reader]) == {:ok, 1}

    assert {:error, %Error.Engine{operation: :write, detail: detail}} =
             write!(context, [reader, tuple("user:bob", "reader", "folder:1")], [])

    assert detail =~ "user:bob reader folder:1"
    assert Fake.tuples(context.agent, context.store) == [reader]
  end

  test "a tuple key on both sides of one call is refused", context do
    cleared = tuple("user:ann", "reader", "folder:1", %Condition{name: "while_cleared"})
    assert write!(context, [], [tuple("user:ann", "reader", "folder:1")]) == {:ok, 1}

    assert {:error, %Error.Engine{detail: detail}} = write!(context, [cleared], [cleared])
    assert detail =~ "deletes and writes user:ann reader folder:1"
  end

  test "a delete matches by the tuple key alone, so a condition on it is no part of the match", context do
    plain = tuple("user:ann", "reader", "folder:1")
    conditioned = tuple("user:ann", "reader", "folder:1", %Condition{name: "while_cleared", context: %{"a" => 1}})

    assert write!(context, [], [conditioned]) == {:ok, 1}
    assert write!(context, [plain], []) == {:ok, 1}
    assert Fake.tuples(context.agent, context.store) == []
  end

  test "a call carrying more changes than one call may is refused", context do
    writes = for id <- 1..(Client.max_tuples_per_write() + 1), do: tuple("user:ann", "reader", "folder:#{id}")

    assert {:error, %Error.Engine{detail: detail}} = write!(context, [], writes)
    assert detail =~ "101 changes"
    assert Fake.tuples(context.agent, context.store) == []
  end

  test "writes fail once the fake has acknowledged the number it was given", context do
    :ok = Fake.fail_after(context.agent, 1)

    assert write!(context, [], [tuple("user:ann", "reader", "folder:1")]) == {:ok, 1}
    assert {:error, %Error.Engine{detail: "the fake was asked to fail this write"}} = write!(context, [], [])

    :ok = Fake.fail_after(context.agent, nil)
    assert write!(context, [], [tuple("user:bob", "reader", "folder:1")]) == {:ok, 1}
  end

  test "read pages by the limit it is given and filters by object, relation, and user", context do
    tuples = for id <- 1..3, do: tuple("user:ann", "reader", "folder:#{id}")
    assert write!(context, [], [tuple("user:bob", "editor", "folder:1") | tuples]) == {:ok, 4}

    assert {:ok, %Page{tuples: first, continuation: continuation}} =
             Fake.read(context.agent, context.store, %Read{object_type: "folder", limit: 2})

    assert length(first) == 2
    assert continuation

    assert {:ok, %Page{tuples: rest, continuation: nil}} =
             Fake.read(context.agent, context.store, %Read{object_type: "folder", limit: 2, continuation: continuation})

    assert length(rest) == 2

    assert {:ok, %Page{tuples: [held], continuation: nil}} =
             Fake.read(context.agent, context.store, %Read{
               object_type: "folder",
               object_id: "1",
               relation: "editor",
               user: "user:bob"
             })

    assert held.user == "user:bob"
    assert {:ok, %Page{tuples: []}} = Fake.read(context.agent, context.store, %Read{object_type: "clearance"})
  end

  test "check and batch_check answer from the tuples the store holds directly", context do
    reader = tuple("user:ann", "reader", "folder:1")
    assert write!(context, [], [reader]) == {:ok, 1}

    assert Fake.check(context.agent, context.store, %Check{tuple_key: reader}) == {:ok, true}

    assert Fake.check(context.agent, context.store, %Check{tuple_key: tuple("user:bob", "reader", "folder:1")}) ==
             {:ok, false}

    batch = %BatchCheck{checks: [{"a", reader}, {"b", tuple("user:bob", "reader", "folder:1")}]}
    assert Fake.batch_check(context.agent, context.store, batch) == {:ok, %{"a" => true, "b" => false}}
  end

  test "list_objects answers the objects of the type the user holds the relation on", context do
    tuples = [tuple("user:ann", "reader", "folder:2"), tuple("user:ann", "reader", "folder:1")]
    assert write!(context, [], [tuple("user:ann", "member", "clearance:cleared") | tuples]) == {:ok, 3}

    request = %ListObjects{user: "user:ann", relation: "reader", type: "folder"}
    assert Fake.list_objects(context.agent, context.store, request) == {:ok, ["folder:1", "folder:2"]}

    assert Fake.list_objects(context.agent, context.store, %{request | relation: "editor"}) == {:ok, []}
  end

  test "expand answers the users the relation holds directly on the object", context do
    tuples = [tuple("user:bob", "reader", "folder:1"), tuple("user:ann", "reader", "folder:1")]
    assert write!(context, [], [tuple("user:ann", "editor", "folder:1") | tuples]) == {:ok, 3}

    assert {:ok, %Tree{users: users, children: []}} =
             Fake.expand(context.agent, context.store, %Expand{relation: "reader", object: "folder:1"})

    assert users == ["user:ann", "user:bob"]
  end

  test "every call is recorded in the order it was made", context do
    assert write!(context, [], []) == {:ok, 0}
    assert {:ok, _page} = Fake.read(context.agent, context.store, %Read{object_type: "folder"})

    assert [{:create_store, "conformance"}, {:write, %Write{}}, {:read, %Read{}}] = Fake.calls(context.agent)
    assert [%Write{deletes: [], writes: []}] = Fake.writes(context.agent)
  end
end
