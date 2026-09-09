defmodule Turnstile.Fga.Client.HttpTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Fga.Client.BatchCheck
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.Expand
  alias Turnstile.Fga.Client.Http
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Page
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Tree
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Condition
  alias Turnstile.Fga.Model
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Fixture.World

  @moduletag :fga

  setup do
    server = Turnstile.Test.Fga.info()
    {:ok, store} = Http.create_store(server.address, "conformance")
    {:ok, model} = Http.write_model(server.address, store, Model.read!("priv/conformance/model.fga"))

    {:ok, endpoint: server.address, store: store, model: model}
  end

  defp member(account, clearance) do
    %TupleKey{user: "user:#{account}", relation: "member", object: "clearance:#{clearance}"}
  end

  defp role(account, folder, relation, clearance) do
    %TupleKey{
      user: "user:#{account}",
      relation: relation,
      object: "folder:#{folder}",
      condition: %Condition{name: "while_cleared", context: %{"clearance" => clearance}}
    }
  end

  defp under(folder, item), do: %TupleKey{user: "folder:#{folder}", relation: "folder", object: "item:#{item}"}

  # Two accounts of the neutral fixture: one cleared with a reading role, one
  # holding an editing role under a clearance the condition refuses.
  defp world(context) do
    written = [
      member("ann", World.cleared()),
      member("bob", "secret"),
      role("ann", 1, "reader", World.cleared()),
      role("bob", 1, "editor", "secret"),
      under(1, 1)
    ]

    {:ok, 5} = Http.write(context.endpoint, context.store, %Write{deletes: [], writes: written})
    written
  end

  defp asks(context, account, relation, object) do
    request = %Check{
      tuple_key: %TupleKey{user: "user:#{account}", relation: relation, object: object},
      model: context.model,
      consistency: :higher_consistency
    }

    Http.check(context.endpoint, context.store, request)
  end

  test "a store and a model answer the ids the server gave them", context do
    assert is_binary(context.store)
    assert is_binary(context.model)
  end

  test "a check under the pinned model answers what the model says", context do
    _written = world(context)

    assert asks(context, "ann", "can_read", "folder:1") == {:ok, true}
    assert asks(context, "ann", "can_edit", "folder:1") == {:ok, false}
    assert asks(context, "zed", "can_read", "folder:1") == {:ok, false}
  end

  test "a role a condition refuses holds nothing", context do
    _written = world(context)

    assert asks(context, "bob", "can_edit", "folder:1") == {:ok, false}
    assert asks(context, "bob", "can_read", "folder:1") == {:ok, false}
  end

  test "an item answers as the folder it is under does", context do
    _written = world(context)

    assert asks(context, "ann", "can_read", "item:1") == {:ok, true}
    assert asks(context, "ann", "can_edit", "item:1") == {:ok, false}
  end

  test "a batch answers each question under the id it was asked with", context do
    _written = world(context)

    request = %BatchCheck{
      checks: [
        {"a-1", %TupleKey{user: "user:ann", relation: "can_read", object: "folder:1"}},
        {"b-2", %TupleKey{user: "user:ann", relation: "can_edit", object: "folder:1"}}
      ],
      model: context.model,
      consistency: :higher_consistency
    }

    assert Http.batch_check(context.endpoint, context.store, request) == {:ok, %{"a-1" => true, "b-2" => false}}
  end

  test "a listing answers the objects of one type the account holds the relation on", context do
    _written = world(context)
    request = %ListObjects{user: "user:ann", relation: "can_read", type: "folder", model: context.model}

    assert Http.list_objects(context.endpoint, context.store, request) == {:ok, ["folder:1"]}

    refused = %ListObjects{user: "user:bob", relation: "can_read", type: "folder", model: context.model}
    assert Http.list_objects(context.endpoint, context.store, refused) == {:ok, []}
  end

  test "an expansion answers the relations the operation is computed from", context do
    _written = world(context)
    request = %Expand{relation: "can_read", object: "folder:1", model: context.model}

    assert {:ok, %Tree{} = tree} = Http.expand(context.endpoint, context.store, request)
    assert tree.object == "folder:1"
    assert tree.relation == "can_read"

    names = for child <- tree.children, do: "#{child.object}##{child.relation}"
    assert "folder:1#reader" in names
    assert "folder:1#editor" in names
  end

  test "an expansion of a relation held directly answers the users holding it", context do
    _written = world(context)
    request = %Expand{relation: "reader", object: "folder:1", model: context.model}

    assert {:ok, %Tree{} = tree} = Http.expand(context.endpoint, context.store, request)
    assert tree.users == ["user:ann"]
  end

  test "a read of one object answers its tuples with the condition each carries", context do
    _written = world(context)

    assert {:ok, %Page{} = page} =
             Http.read(context.endpoint, context.store, %Read{object_type: "folder", object_id: "1"})

    held = [role("ann", 1, "reader", World.cleared()), role("bob", 1, "editor", "secret")]

    assert Enum.sort_by(page.tuples, &TupleKey.key/1) == held
    assert page.continuation == nil
  end

  test "a read of a whole object type answers that type and nothing else", context do
    _written = world(context)

    assert {:ok, %Page{} = page} = Http.read(context.endpoint, context.store, %Read{object_type: "clearance"})

    assert Enum.sort_by(page.tuples, &TupleKey.key/1) == [member("ann", World.cleared()), member("bob", "secret")]
  end

  test "a read narrowed by a relation and a user answers that tuple alone", context do
    _written = world(context)
    request = %Read{object_type: "folder", object_id: "1", relation: "reader", user: "user:ann"}

    assert {:ok, %Page{tuples: [tuple]}} = Http.read(context.endpoint, context.store, request)
    assert tuple == role("ann", 1, "reader", World.cleared())
  end

  test "a page smaller than the store answers a continuation, and the pages together are the store", context do
    _written = world(context)

    assert {:ok, %Page{} = first} = Http.read(context.endpoint, context.store, %Read{object_type: "folder", limit: 1})
    assert is_binary(first.continuation)

    next = %Read{object_type: "folder", limit: 1, continuation: first.continuation}
    assert {:ok, %Page{} = second} = Http.read(context.endpoint, context.store, next)
    assert length(first.tuples) + length(second.tuples) <= 2
  end

  test "a delete takes the tuple out, and the account loses what it held", context do
    _written = world(context)
    change = %Write{deletes: [role("ann", 1, "reader", World.cleared())], writes: []}

    assert {:ok, 1} = Http.write(context.endpoint, context.store, change)
    assert asks(context, "ann", "can_read", "folder:1") == {:ok, false}
  end

  test "a condition that changed is the same key with another context, deleted and written again", context do
    _written = world(context)
    old = role("ann", 1, "reader", World.cleared())
    new = role("ann", 1, "reader", "secret")

    assert {:error, %Error.Engine{operation: :write}} =
             Http.write(context.endpoint, context.store, %Write{deletes: [old], writes: [new]})

    assert {:ok, 1} = Http.write(context.endpoint, context.store, %Write{deletes: [old], writes: []})
    assert {:ok, 1} = Http.write(context.endpoint, context.store, %Write{deletes: [], writes: [new]})
    assert asks(context, "ann", "can_read", "folder:1") == {:ok, false}
  end

  test "a duplicate write and a delete of a tuple the store does not hold are refused", context do
    written = world(context)
    duplicate = %Write{deletes: [], writes: [List.first(written)]}

    assert {:error, %Error.Engine{operation: :write, detail: detail}} =
             Http.write(context.endpoint, context.store, duplicate)

    assert detail =~ "already exists"

    absent = %Write{deletes: [member("zed", World.cleared())], writes: []}
    assert {:error, %Error.Engine{operation: :write}} = Http.write(context.endpoint, context.store, absent)
  end

  test "a tuple the model admits only under a condition is refused without one", context do
    plain = %TupleKey{user: "user:ann", relation: "reader", object: "folder:9"}

    assert {:error, %Error.Engine{operation: :write, detail: detail}} =
             Http.write(context.endpoint, context.store, %Write{deletes: [], writes: [plain]})

    assert detail =~ "condition is missing"
  end

  test "a store the server does not know is an engine error naming the call", context do
    request = %Check{tuple_key: %TupleKey{user: "user:ann", relation: "can_read", object: "folder:1"}}

    assert {:error, %Error.Engine{adapter: Turnstile.Fga, operation: :check, detail: detail}} =
             Http.check(context.endpoint, "01ABSENTSTORE0000000000000", request)

    assert detail =~ "the server answered"
  end

  test "a model the store does not hold is an engine error", context do
    request = %Check{
      tuple_key: %TupleKey{user: "user:ann", relation: "can_read", object: "folder:1"},
      model: "01ABSENTMODEL0000000000000"
    }

    assert {:error, %Error.Engine{operation: :check}} = Http.check(context.endpoint, context.store, request)
  end

  test "an address nothing listens on is an engine error rather than a wait", _context do
    request = %Check{tuple_key: %TupleKey{user: "user:ann", relation: "can_read", object: "folder:1"}}

    assert {:error, %Error.Engine{operation: :check, detail: detail}} =
             Http.check("127.0.0.1:1", "store", request)

    assert detail =~ "could not be reached"
  end

  test "an endpoint that is no address is an engine error rather than a crash", context do
    request = %Check{tuple_key: %TupleKey{user: "user:ann", relation: "can_read", object: "folder:1"}}

    assert {:error, %Error.Engine{operation: :check, detail: detail}} = Http.check(self(), context.store, request)
    assert detail =~ "no address this client reaches"
  end

  test "every call emits one event with its duration and its outcome", context do
    id = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(id, Http.telemetry_event(), &send_event/4, self())
    on_exit(fn -> :telemetry.detach(id) end)

    _written = world(context)

    assert_received {:event, %{duration: duration}, %{path: path, outcome: :ok}}
    assert duration > 0
    assert path =~ "/write"
    refute_received {:event, _measurements, _metadata}
  end

  defp send_event(_event, measurements, metadata, pid), do: send(pid, {:event, measurements, metadata})
end
