defmodule OutsideCaller do
  @moduledoc false
  # A caller outside `Turnstile.*`, for the library exemption's refusal. The
  # tuple keeps the Sandboxed call off the tail position, so the frame stays.

  @spec read(module(), term()) :: {:read, term()}
  def read(repo, option), do: {:read, repo.all(Turnstile.Fixture.Folder, turnstile: option)}
end

defmodule Turnstile.Repo.SeamTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Turnstile.Adapter.Fake
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Id
  alias Turnstile.Ledger.Memory
  alias Turnstile.Reason
  alias Turnstile.Subject
  alias Turnstile.Test.AroundAdapter
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Owner
  alias Turnstile.TestRepos.Sandboxed

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    {:ok, agent} = Memory.start_link()
    :ok = Turnstile.Test.with_config(adapter: Fake, ledger: {Memory, agent: agent})
    folder = Sandboxed.insert!(%Folder{name: "root"}, turnstile: {:exempt, "seed"})
    item = Sandboxed.insert!(%Item{title: "first", folder_id: folder.id}, turnstile: {:exempt, "seed"})
    %{agent: agent, folder: folder, item: item, decision: decision(:folder, folder.id)}
  end

  describe "the query bucket" do
    test "all under a decision for the root's type runs, and for another type is refused", %{decision: decision} do
      assert [%Folder{}] = Sandboxed.all(Folder, turnstile: decision)

      error = assert_raise(Error.Unmediated, fn -> Sandboxed.all(Item, turnstile: decision) end)
      assert %Error.Unmediated{function: :all, arity: 2, schema: Item, object_type: :folder} = error
      assert Exception.message(error) =~ "carries a decision for :folder, which does not cover it"
    end

    test "a query without the option is refused naming the function and the caller" do
      error =
        assert_raise(Error.Unmediated, fn ->
          returned = Sandboxed.one(Folder)
          flunk("returned " <> inspect(returned))
        end)

      assert %Error.Unmediated{function: :one, arity: 2, schema: Folder, caller: __MODULE__} = error

      assert Exception.message(error) ==
               "Repo.one/2 on Turnstile.Fixture.Folder carries no decision and no exemption (from Turnstile.Repo.SeamTest)"
    end

    test "an unprotected schema passes without a decision" do
      assert [] = Sandboxed.all(Membership)
      assert Sandboxed.aggregate(Account, :count) == 0
    end

    test "preload of a carried association is allowed and of an uncarried protected schema is refused",
         %{folder: folder, item: item, decision: decision} do
      assert %Folder{items: [%Item{}]} = Sandboxed.preload(folder, :items, turnstile: decision)
      assert %Folder{memberships: []} = Sandboxed.preload(folder, :memberships, turnstile: decision)

      assert_raise Error.Unmediated, ~r/on Turnstile.Fixture.Folder/, fn ->
        Sandboxed.preload(item, :folder, turnstile: decision(:item, item.id))
      end
    end

    test "preload without a decision is refused", %{folder: folder} do
      assert_raise Error.Unmediated, ~r/Repo.preload\/3/, fn -> Sandboxed.preload(folder, :items) end
    end

    test "a join with a carried source is allowed and with an uncarried protected source is refused",
         %{decision: decision, item: item} do
      carried = from(f in Folder, join: i in assoc(f, :items), select: i.title)
      assert ["first"] = Sandboxed.all(carried, turnstile: decision)

      uncarried = from(i in Item, join: f in assoc(i, :folder), select: f.name)

      assert_raise Error.Unmediated, ~r/on Turnstile.Fixture.Folder/, fn ->
        Sandboxed.all(uncarried, turnstile: decision(:item, item.id))
      end

      by_source = from(i in Item, join: f in Folder, on: f.id == i.folder_id, select: f.name)
      assert_raise Error.Unmediated, fn -> Sandboxed.all(by_source, turnstile: decision(:item, item.id)) end
    end

    test "aggregate, exists?, get, get_by, all_by, reload, and stream carry the decision",
         %{folder: folder, decision: decision} do
      assert Sandboxed.aggregate(Folder, :count, turnstile: decision) == 1
      assert Sandboxed.aggregate(Folder, :max, :id, turnstile: decision) == folder.id
      assert Sandboxed.exists?(Folder, turnstile: decision)
      assert %Folder{} = Sandboxed.get(Folder, folder.id, turnstile: decision)
      assert %Folder{} = Sandboxed.get_by(Folder, [name: "root"], turnstile: decision)
      assert [%Folder{}] = Sandboxed.all_by(Folder, [name: "root"], turnstile: decision)
      assert %Folder{} = Sandboxed.reload(folder, turnstile: decision)

      assert [%Folder{}] =
               fn -> Enum.to_list(Sandboxed.stream(Folder, turnstile: decision)) end
               |> Sandboxed.transaction()
               |> elem(1)

      assert_raise Error.Unmediated, fn -> Sandboxed.aggregate(Folder, :count) end
      assert_raise Error.Unmediated, fn -> Sandboxed.exists?(Folder) end
      assert_raise Error.Unmediated, fn -> Sandboxed.reload(folder) end
      assert_raise Error.Unmediated, fn -> Sandboxed.transaction(fn -> Sandboxed.stream(Folder) end) end
    end

    test "a subquery root is judged by its inner source", %{decision: decision} do
      query = from(s in subquery(from(f in Folder, select: %{id: f.id})), select: s.id)
      assert [_id] = Sandboxed.all(query, turnstile: decision)
      assert_raise Error.Unmediated, fn -> Sandboxed.all(query) end
    end

    test "a denied decision raises NotAuthorized before the query", %{folder: folder} do
      denied = %{decision(:folder, folder.id) | verdict: :deny}
      assert_raise Error.NotAuthorized, fn -> Sandboxed.all(Folder, turnstile: denied) end
    end

    test "an unknown option shape is refused as invalid" do
      assert_raise NimbleOptions.ValidationError, fn -> Sandboxed.all(Folder, turnstile: :please) end
      assert_raise NimbleOptions.ValidationError, fn -> Sandboxed.all(Folder, turnstile: {:exempt, ""}) end
    end
  end

  describe "exemptions" do
    test "a declared exemption admits the call and a library exemption from outside the library is refused" do
      assert [%Folder{}] = Sandboxed.all(Folder, turnstile: {:exempt, "report"})

      assert {:read, [%Folder{}]} = OutsideCaller.read(Sandboxed, {:exempt, "report"})
      error = assert_raise(Error.Unmediated, fn -> OutsideCaller.read(Sandboxed, {:exempt, :library}) end)
      assert error.caller == OutsideCaller
      assert Exception.message(error) =~ "accepted only from a Turnstile.* caller"
    end

    test "the owner-role repo needs no option", %{folder: folder} do
      # The owner repo connects to the committed database, where the sandboxed rows are not visible.
      query = from(f in Folder, where: f.id == ^folder.id)
      assert [] = Owner.all(query)
      assert %{rows: [[1]]} = Owner.query!("SELECT 1")
    end
  end

  describe "the raw bucket" do
    test "query/3 without an exemption is refused, with a decision is invalid, with an exemption runs", %{
      decision: decision
    } do
      assert_raise Error.Unmediated, ~r/Repo.query\/3/, fn -> Sandboxed.query("SELECT 1", [], []) end
      assert_raise Error.Unmediated, ~r/Repo.query\/3/, fn -> Sandboxed.query("SELECT 1") end

      assert_raise Error.Invalid, ~r/takes an exemption, not a decision/, fn ->
        Sandboxed.query("SELECT 1", [], turnstile: decision)
      end

      assert {:ok, %{rows: [[1]]}} = Sandboxed.query("SELECT 1", [], turnstile: {:exempt, "probe"})
      assert %{rows: [[1]]} = Sandboxed.query!("SELECT 1", [], turnstile: {:exempt, "probe"})
    end
  end

  describe "the write bucket" do
    test "a write on a protected schema needs a decision for its type", %{folder: folder, decision: decision} do
      assert {:ok, %Folder{name: "renamed"}} =
               folder
               |> Changeset.change(name: "renamed")
               |> Sandboxed.update(turnstile: decision)

      assert_raise Error.Unmediated, ~r/Repo.insert\/2 on Turnstile.Fixture.Folder/, fn ->
        Sandboxed.insert(%Folder{name: "other"})
      end

      assert_raise Error.Unmediated, ~r/decision for :folder/, fn ->
        Sandboxed.insert!(%Item{title: "x"}, turnstile: decision)
      end

      assert_raise Error.Unmediated, fn -> Sandboxed.delete(folder) end
    end

    test "a nested write of a carried schema is allowed and of an uncarried protected schema is refused",
         %{folder: folder, item: item, decision: decision} do
      loaded = Sandboxed.preload(folder, :items, turnstile: decision)

      changeset =
        loaded
        |> Changeset.change()
        |> Changeset.put_assoc(:items, [%Item{title: "second"} | loaded.items])

      assert {:ok, %Folder{items: items}} = Sandboxed.update(changeset, turnstile: decision)
      assert length(items) == 2

      nested =
        %{item | folder: nil}
        |> Changeset.change()
        |> Changeset.put_assoc(:folder, %Folder{name: "new parent"})

      assert_raise Error.Unmediated, ~r/on Turnstile.Fixture.Folder/, fn ->
        Sandboxed.update(nested, turnstile: decision(:item, item.id))
      end
    end

    test "insert_all with entries and with a query source carries a decision for the root's type",
         %{folder: folder, item: item, decision: decision} do
      items = decision(:item, item.id)
      assert {1, nil} = Sandboxed.insert_all(Item, [%{title: "bulk", folder_id: folder.id}], turnstile: items)
      source = from(i in Item, select: %{title: i.title, folder_id: i.folder_id})
      assert {2, nil} = Sandboxed.insert_all(Item, source, turnstile: items)
      assert_raise Error.Unmediated, fn -> Sandboxed.insert_all(Item, [%{title: "bulk"}]) end

      assert_raise Error.Unmediated, ~r/carries a decision for :folder/, fn ->
        Sandboxed.insert_all(Item, [%{title: "bulk"}], turnstile: decision)
      end
    end

    test "update_all and delete_all on a protected schema carry the decision", %{item: item, decision: decision} do
      assert {1, nil} = Sandboxed.update_all(Folder, [set: [name: "all"]], turnstile: decision)
      assert_raise Error.Unmediated, fn -> Sandboxed.update_all(Folder, set: [name: "none"]) end
      assert {1, nil} = Sandboxed.delete_all(Item, turnstile: decision(:item, item.id))

      assert_raise Error.Unmediated, ~r/carries a decision for :folder/, fn ->
        Sandboxed.delete_all(Item, turnstile: decision)
      end

      assert_raise Error.Unmediated, fn -> Sandboxed.delete_all(Folder) end
    end

    test "an Ecto.Multi run through transaction carries each operation's own option",
         %{folder: folder, item: item, decision: decision} do
      multi =
        Multi.new()
        |> Multi.insert(:item, %Item{title: "in multi", folder_id: folder.id}, turnstile: decision(:item, item.id))
        |> Multi.update_all(:rename, Folder, [set: [name: "multi"]], turnstile: decision)

      assert {:ok, %{item: %Item{}, rename: {1, nil}}} = Sandboxed.transaction(multi)

      unmediated = Multi.insert(Multi.new(), :item, %Item{title: "no option"})
      assert_raise Error.Unmediated, fn -> Sandboxed.transaction(unmediated) end
    end

    test "an upsert on a fact schema is refused naming the schema", %{folder: folder} do
      membership = %Membership{account_id: "acct-1", role: :reader, folder_id: folder.id}
      error = assert_raise(Error.Invalid, fn -> Sandboxed.insert(membership, on_conflict: :nothing) end)
      assert error.what == :upsert
      assert Exception.message(error) =~ "on Turnstile.Fixture.Membership"
      assert Exception.message(error) =~ "bulk_insert/3"
    end

    test "a bulk write to fact fields is refused and pointed at the bulk API, exemption or not", %{folder: folder} do
      assert_raise Error.Invalid, ~r/bulk_update/, fn -> Sandboxed.update_all(Membership, set: [role: :editor]) end
      assert_raise Error.Invalid, ~r/bulk_delete/, fn -> Sandboxed.delete_all(Membership) end

      assert_raise Error.Invalid, ~r/bulk_insert/, fn ->
        Sandboxed.insert_all(Membership, [%{account_id: "a", role: :reader, folder_id: folder.id}])
      end

      assert_raise Error.Invalid, ~r/bulk_update/, fn ->
        Sandboxed.update_all(Account, set: [clearance: "none"], turnstile: {:exempt, "unchanged"})
      end
    end

    test "in ledger mode none a bulk write to fact fields runs" do
      Turnstile.Test.with_config(ledger: :none)
      assert {0, nil} = Sandboxed.update_all(Account, set: [clearance: "none"])
    end
  end

  describe "fact recording" do
    test "a relationship insert, update, and delete append events with old from the re-read row",
         %{folder: folder, agent: agent} do
      subject = %Subject{id: "user-9", kind: :user}
      decision = %{decision(:folder, folder.id) | subject: subject}

      membership =
        Sandboxed.insert!(%Membership{account_id: "acct-1", role: :reader, folder_id: folder.id},
          turnstile: {:exempt, "grant"}
        )

      assert {:ok, [%FactEvent{kind: :relationship, old: nil, new: :reader, position: 1} = inserted]} =
               Memory.read([agent: agent], 0, 10)

      assert inserted.subject_ref == {:user, "acct-1"}
      assert inserted.object_ref == {:folder, folder.id}
      assert inserted.by == Subject.library()

      assert {:ok, _updated} =
               membership
               |> Changeset.change(role: :editor)
               |> Sandboxed.update(turnstile: decision)

      assert {:ok, [_inserted, %FactEvent{attribute: :role, old: :reader, new: :editor, by: ^subject} = updated]} =
               Memory.read([agent: agent], 0, 10)

      assert updated.operation_id == decision.operation_id

      # The stale struct still says reader; old comes from the re-read row, which says editor.
      assert {:ok, _deleted} = Sandboxed.delete(membership, turnstile: {:exempt, "revoke"})

      assert {:ok, [_inserted, _updated, %FactEvent{old: :editor, new: nil, position: 3}]} =
               Memory.read([agent: agent], 0, 10)
    end

    test "a fact column write appends one event per changed column and an unchanged write appends none", %{agent: agent} do
      account = Sandboxed.insert!(%Account{id: "acct-2", clearance: "secret"})

      assert {:ok, [%FactEvent{kind: :subject_attribute, attribute: :clearance, old: nil, new: "secret"}]} =
               Memory.read([agent: agent], 0, 10)

      assert {:ok, _same} =
               account
               |> Changeset.change(clearance: "secret")
               |> Sandboxed.update()

      assert {:ok, [_one]} = Memory.read([agent: agent], 0, 10)

      assert %Account{} =
               account
               |> Changeset.change(clearance: "top")
               |> Sandboxed.update!()

      assert {:ok, [_one, %FactEvent{old: "secret", new: "top", subject_ref: {:user, "acct-2"}}]} =
               Memory.read([agent: agent], 0, 10)
    end

    test "a write that fails appends nothing and returns the error", %{agent: agent} do
      changeset =
        %Account{id: "acct-3"}
        |> Changeset.change(clearance: "x")
        |> Changeset.add_error(:clearance, "no")

      assert {:error, %Changeset{}} = Sandboxed.insert(changeset)
      assert {:ok, []} = Memory.read([agent: agent], 0, 10)
      refute Sandboxed.in_transaction?()
    end

    test "in ledger mode none a fact write records nothing", %{agent: agent} do
      Turnstile.Test.with_config(ledger: :none)
      assert %Account{} = Sandboxed.insert!(%Account{id: "acct-4", clearance: "secret"})
      assert {:ok, []} = Memory.read([agent: agent], 0, 10)
    end
  end

  describe "the seam's edges" do
    test "insert_or_update inserts a new struct and updates a loaded one", %{folder: folder, decision: decision} do
      assert {:ok, %Folder{id: id}} =
               Sandboxed.insert_or_update(Changeset.change(%Folder{name: "fresh"}), turnstile: decision(:folder, nil))

      assert {:ok, %Folder{id: ^id, name: "kept"}} =
               %Folder{id: id, name: "fresh"}
               |> Ecto.put_meta(state: :loaded)
               |> Changeset.change(name: "kept")
               |> Sandboxed.insert_or_update(turnstile: decision(:folder, id))

      assert {:ok, %Folder{name: "again"}} =
               folder
               |> Changeset.change(name: "again")
               |> Sandboxed.insert_or_update(turnstile: decision)
    end

    test "delete_all and update_all on a table name pass, as the name declares no object type" do
      assert {0, nil} = Sandboxed.delete_all("turnstile_fixture_accounts")
      assert {0, nil} = Sandboxed.update_all("turnstile_fixture_accounts", set: [clearance: "none"])
    end

    test "prepare_query reached outside an override judges the query with an empty mediation" do
      query = Ecto.Queryable.to_query(Folder)

      error =
        assert_raise(Error.Unmediated, fn ->
          prepared = Sandboxed.prepare_query(:all, query, [])
          flunk("prepared " <> inspect(prepared))
        end)

      assert %Error.Unmediated{function: :all, arity: 2, schema: Folder, caller: __MODULE__} = error

      error = assert_raise(Error.Unmediated, fn -> Sandboxed.prepare_query(:update_all, query, []) end)
      assert %Error.Unmediated{function: :update_all, arity: 3} = error

      unprotected = Ecto.Queryable.to_query(Account)
      assert {^unprotected, []} = Sandboxed.prepare_query(:all, unprotected, [])
    end
  end

  describe "around_query" do
    test "the adapter's around_query receives the query or changeset and the decision", %{
      folder: folder,
      decision: decision
    } do
      Turnstile.Test.with_config(adapter: AroundAdapter)
      assert [%Folder{}] = Sandboxed.all(Folder, turnstile: decision)
      assert_received {:around_query, %Ecto.Query{}, ^decision}

      assert {:ok, _folder} =
               folder
               |> Changeset.change(name: "wrapped")
               |> Sandboxed.update(turnstile: decision)

      assert_received {:around_query, %Changeset{}, ^decision}

      assert [%Folder{}] = Sandboxed.all(Folder, turnstile: {:exempt, "no wrap"})
      refute_received {:around_query, _query, _decision}
    end
  end

  defp decision(type, id) do
    %Decision{
      id: Id.new(),
      subject: %Subject{id: "user-1", kind: :user},
      object: {type, id},
      operation: :read,
      verdict: :allow,
      reason: %Reason{code: :allowed, message: "allowed by the fake adapter"},
      adapter: Fake,
      policy_version: nil,
      head_position: nil,
      applied_position: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }
  end
end
