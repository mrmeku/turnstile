defmodule Turnstile.PostgresTest do
  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL.Sandbox
  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Fixture.Account
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Id
  alias Turnstile.Postgres
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Conformance.Rules
  alias Turnstile.Postgres.Infrastructure.Session
  alias Turnstile.Postgres.Infrastructure.Settings
  alias Turnstile.TestRepos.Sandboxed

  @schemas [Account, Folder, Item, Membership]
  @subject {:user, "account-1"}
  @object {:folder, 1}

  test "the declaration: no scope cap, and a replica lag the adapter cannot measure" do
    assert Postgres.scope_cap() == :none
    assert Postgres.replica_lag() == "not measured"
  end

  test "with nothing bound every callback answers an engine error naming the callback" do
    assert {:error, %Error{reason: :engine_unreachable, detail: detail}} =
             Postgres.decide(@subject, :read, @object, environment(), [])

    assert detail == "#{inspect(Postgres)} failed during decide: invalid binding: nothing bound and no override"

    assert {:error, %Error{reason: :engine_unreachable, detail: "Turnstile.Postgres failed during scope" <> _rest}} =
             Postgres.scope(@subject, :read, :folder, environment(), [])

    assert_raise Error, fn -> Postgres.load!() end
  end

  test "load! reads the catalog once, and a second call reads nothing" do
    bind()

    assert %Catalog{version: version, policies: [_policy | _rest]} = Postgres.load!()
    assert version == to_string(Rules.version())
    assert Postgres.load!() == Postgres.load!()
  end

  test "reload! reads the catalog again, for an application that ran a migration after boot" do
    assert_raise Error, fn -> Postgres.reload!() end

    bind()

    assert %Catalog{policies: [_policy | _rest]} = reloaded = Postgres.reload!()
    assert Postgres.load!() == reloaded
  end

  test "a catalog the engine cannot read is an engine error naming the callback" do
    bind(migrations_table: "turnstile_no_such_table")

    assert {:error, %Error{reason: :engine_unreachable, detail: detail}} =
             Postgres.decide(@subject, :read, @object, environment(), [])

    assert detail =~ "Turnstile.Postgres failed during decide"
    assert detail =~ "turnstile_no_such_table"
  end

  test "an object type no bound schema declares is denied by default" do
    bind()

    assert {:ok, %Answer{verdict: :deny, reason: :deny_by_default}} =
             Postgres.decide(@subject, :read, {:no_such_type, 1}, environment(), [])
  end

  test "an operation with no policy on the type denies the scope" do
    bind()

    assert {:ok, {_rule, %Answer{verdict: :deny, reason: :unknown_operation}}} =
             Postgres.scope(@subject, :publish, :folder, environment(), [])
  end

  test "a scope names the policy and the hash of the settings the database will read" do
    bind()
    settings = Settings.of(@subject, :read, environment())

    assert {:ok, {_rule, %Answer{verdict: :allow} = answer}} =
             Postgres.scope(@subject, :read, :folder, environment(), [])

    assert answer.reason == :allowed
    assert answer.meta.rule == "turnstile_scope_read settings sha256:#{Settings.hash(settings)}"
    assert Session.recall(@subject, :read) == settings
  end

  test "around_query runs the settings of the call that produced the decision" do
    bind()
    settings = Settings.of(@subject, :read, environment())
    :ok = Session.remember(@subject, :read, settings)

    assert Postgres.around_query(Folder, decision(), fn -> setting("turnstile.subject_id") end) == "account-1"
  end

  test "the session keeps one slot per subject and operation, so a review recalls every subject's call" do
    bind()
    other = {:user, "account-2"}
    facts = Map.put(environment(), :clearance, "cleared")
    mine = Settings.of(@subject, :read, facts)
    theirs = Settings.of(other, :read, facts)
    :ok = Session.remember(@subject, :read, mine)
    :ok = Session.remember(other, :read, theirs)

    assert Session.recall(@subject, :read) == mine
    assert Session.recall(other, :read) == theirs
    assert Session.recall(@subject, :publish) == nil
  end

  test "around_query with the call out of reach sets what the decision alone determines" do
    bind()

    assert Postgres.around_query(Folder, decision(), fn -> setting("turnstile.operation") end) == "read"
  end

  test "around_query with nothing bound runs the function and sets nothing" do
    assert Postgres.around_query(Folder, decision(), fn -> :ran end) == :ran
  end

  test "a mediated call inside another leaves behind the settings of the call around it" do
    bind()
    inner = {:user, "account-2"}

    read =
      Postgres.around_query(Folder, decision(), fn ->
        nested = Postgres.around_query(Folder, decision(inner), fn -> setting("turnstile.subject_id") end)
        {nested, setting("turnstile.subject_id")}
      end)

    assert read == {"account-2", "account-1"}
    assert setting("turnstile.subject_id") == ""
  end

  defp environment(facts \\ %{}) do
    Map.put(facts, :now, ~U[2026-09-08 12:00:00Z])
  end

  defp decision(subject \\ @subject) do
    %Decision{
      id: Id.new(),
      subject: subject,
      object: {:folder, 1},
      operation: :read,
      verdict: :allow,
      reason: :allowed,
      adapter: Postgres,
      policy_version: nil,
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
