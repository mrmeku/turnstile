defmodule Turnstile.PostgresTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Id
  alias Turnstile.Object
  alias Turnstile.Postgres
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Conformance.Rules
  alias Turnstile.Postgres.Session
  alias Turnstile.Postgres.Settings
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject
  alias Turnstile.TestRepos.Sandboxed

  @schemas [Account, Folder, Item, Membership]
  @subject %Subject{id: "account-1", kind: :user}
  @object %Object{type: :folder, id: 1}

  test "the declaration: no ledger, no scope cap, and a replica lag the adapter cannot measure" do
    assert Postgres.requires_ledger() == false
    assert Postgres.scope_cap() == :none
    assert Postgres.replica_lag() == "not measured"
  end

  test "with nothing bound every callback answers an engine error naming the callback" do
    assert {:error, %Error.Engine{adapter: Postgres, operation: :authorize, detail: detail}} =
             Postgres.authorize(@subject, :read, @object, environment(), [])

    assert detail == "nothing bound and no override"
    assert {:error, %Error.Engine{operation: :batch}} = Postgres.batch(@subject, :read, [@object], environment(), [])
    assert {:error, %Error.Engine{operation: :scope}} = Postgres.scope(@subject, :read, :folder, environment(), [])
    assert_raise Error.Invalid, fn -> Postgres.load!() end
  end

  test "load! reads the catalog once, and a second call reads nothing" do
    bind()

    assert %Catalog{version: version, policies: [_policy | _rest]} = Postgres.load!()
    assert version == to_string(Rules.version())
    assert Postgres.load!() == Postgres.load!()
  end

  test "reload! reads the catalog again, for an application that ran a migration after boot" do
    assert_raise Error.Invalid, fn -> Postgres.reload!() end

    bind()

    assert %Catalog{policies: [_policy | _rest]} = reloaded = Postgres.reload!()
    assert Postgres.load!() == reloaded
  end

  test "a catalog the engine cannot read is an engine error naming the callback" do
    bind(migrations_table: "turnstile_no_such_table")

    assert {:error, %Error.Engine{adapter: Postgres, operation: :authorize, detail: detail}} =
             Postgres.authorize(@subject, :read, @object, environment(), [])

    assert detail =~ "turnstile_no_such_table"
  end

  test "an object type no bound schema declares is denied by default, and explain names nothing further" do
    bind()

    assert {:ok, %Explanation{answer: %Answer{verdict: :deny} = answer, matched: []}} =
             Postgres.explain(@subject, :read, %Object{type: :ledger_entry, id: 1}, environment(), [])

    assert answer.reason == Reason.deny_by_default()
  end

  test "an operation with no policy on the type denies the scope" do
    bind()

    assert {:ok, %Scope{answer: %Answer{verdict: :deny} = answer}} =
             Postgres.scope(@subject, :publish, :folder, environment(), [])

    assert answer.reason == Reason.unknown_operation(:publish)
  end

  test "a scope names the policy and the hash of the settings the database will read" do
    bind()
    settings = Settings.of(@subject, :read, environment())

    assert {:ok, %Scope{answer: %Answer{verdict: :allow} = answer}} =
             Postgres.scope(@subject, :read, :folder, environment(), [])

    assert answer.reason == Reason.allowed("turnstile_scope_read settings sha256:#{Settings.hash(settings)}")
    assert Session.recall(@subject, :read) == settings
  end

  test "a batch of no objects asks the database nothing" do
    bind()
    assert Postgres.batch(@subject, :read, [], environment(), []) == {:ok, %{}}
  end

  test "around_query runs the settings of the call that produced the decision" do
    bind()
    settings = Settings.of(@subject, :read, environment())
    :ok = Session.remember(@subject, :read, settings)

    assert Postgres.around_query(Folder, decision(), fn -> setting("turnstile.subject_id") end) == "account-1"
  end

  test "around_query with the call out of reach sets what the decision alone determines" do
    bind()

    assert Postgres.around_query(Folder, decision(), fn -> setting("turnstile.operation") end) == "read"
  end

  test "around_query with nothing bound runs the function and sets nothing" do
    assert Postgres.around_query(Folder, decision(), fn -> :ran end) == :ran
  end

  defp environment(facts \\ %{}) do
    %Environment{now: ~U[2026-09-08 12:00:00Z], facts: facts}
  end

  defp decision do
    %Decision{
      id: Id.new(),
      subject: @subject,
      object: {:folder, 1},
      operation: :read,
      verdict: :allow,
      reason: Reason.allowed("turnstile_scope_read"),
      adapter: Postgres,
      policy_version: nil,
      head_position: nil,
      applied_position: nil,
      operation_id: Id.new(),
      at: ~U[2026-09-08 12:00:00Z]
    }
  end

  defp setting(name) do
    %{rows: [[value]]} = Sandboxed.query!("SELECT current_setting($1, true)", [name], turnstile: {:exempt, "test"})
    value
  end

  defp bind(overrides \\ []) do
    :ok = Sandbox.checkout(Sandboxed)
    Binding.override(Keyword.merge([repo: Sandboxed, schemas: @schemas], overrides))
  end
end
