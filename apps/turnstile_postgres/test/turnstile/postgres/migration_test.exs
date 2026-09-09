defmodule Turnstile.Postgres.MigrationTest do
  use ExUnit.Case, async: false

  alias Turnstile.Error
  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Binding
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Migration
  alias Turnstile.Postgres.Probe
  alias Turnstile.TestRepos.Owner

  @moduletag :committed

  @probe "turnstile_probe_rows"
  @table "turnstile_migration_test_rows"
  @using "current_setting('turnstile.probe', true) = label"

  setup do
    _created = Owner.query!("CREATE TABLE #{@table} (id bigserial PRIMARY KEY, label text)")
    on_exit(fn -> Owner.query!("DROP TABLE IF EXISTS #{@table}") end)
    :ok
  end

  test "protect! turns row-level security on and forces it on the table's owner too" do
    assert Migration.protect!(Owner, @table) == :ok
    assert security() == [true, true]
  end

  test "policy! guards the operation, so the policy of one operation cannot widen another" do
    assert Migration.policy!(Owner, table: @table, operation: :read, using: @using) == :ok
    assert Migration.policy!(Owner, table: @table, operation: :edit, using: @using) == :ok

    assert [edit, read] = policies()
    assert {read.name, read.command} == {"turnstile_scope_read", :select}
    assert read.using =~ "current_setting('turnstile.operation'::text, true) = 'read'::text"
    assert read.using =~ "label"
    assert read.with_check == nil
    assert {edit.name, edit.command} == {"turnstile_scope_edit", :select}
    assert edit.using =~ "'edit'::text"
  end

  test "a gate carries no operation guard, so the database refuses the write whether or not anything asked" do
    assert Migration.gate!(Owner, table: @table, operation: :edit, using: @using, with_check: @using) == :ok

    assert [gate] = policies()
    assert {gate.name, gate.command} == {"turnstile_gate_edit", :update}
    refute gate.using =~ "turnstile.operation"
    assert gate.with_check == gate.using
  end

  test "an operation whose write is an insert has no row to read first, so its gate checks the new row alone" do
    assert Migration.gate!(Owner, table: @table, operation: :add, command: :insert, with_check: @using) == :ok

    assert [gate] = policies()
    assert {gate.name, gate.command} == {"turnstile_gate_add", :insert}
    assert gate.using == nil
    assert gate.with_check =~ "label"
  end

  test "admit! adds the permissive true policy a command needs under forced row-level security" do
    Enum.each([:insert, :delete, :select, :update], &(:ok = Migration.admit!(Owner, table: @table, command: &1)))

    assert [delete, insert, select, update] = policies()
    assert {delete.name, delete.command, delete.using} == {"turnstile_admit_delete", :delete, "true"}
    assert {insert.name, insert.command, insert.with_check} == {"turnstile_admit_insert", :insert, "true"}
    assert {select.name, select.command, select.using} == {"turnstile_admit_select", :select, "true"}
    assert {update.command, update.using, update.with_check} == {:update, "true", "true"}
  end

  test "exempt! admits the role's statements while no operation is in force" do
    assert Migration.exempt!(Owner, table: @table, to: "turnstile_app") == :ok

    assert [delete, insert, select, update] = policies()
    assert {select.name, select.command} == {"turnstile_exempt_turnstile_app_select", :select}
    assert Enum.all?([delete, insert, select, update], &(expression(&1) =~ "turnstile_app"))
    assert Enum.all?([delete, insert, select, update], &(expression(&1) =~ "turnstile.operation"))
    assert {insert.name, insert.using} == {"turnstile_exempt_turnstile_app_insert", nil}
    assert {delete.name, delete.with_check} == {"turnstile_exempt_turnstile_app_delete", nil}
    assert update.with_check == update.using
  end

  test "a role whose reads are unfiltered takes the policy without the operation clause" do
    assert Migration.exempt!(Owner, table: @table, to: "turnstile_owner", commands: [:select], outside_decision: false) ==
             :ok

    assert [policy] = policies()
    assert policy.name == "turnstile_exempt_turnstile_owner_select"
    assert policy.using =~ "turnstile_owner"
    refute policy.using =~ "turnstile.operation"
  end

  test "grant! is what lets the role reach the table at all" do
    refute privilege("SELECT")

    assert Migration.grant!(Owner, table: @table, to: "turnstile_app", commands: [:select, :insert, :update, :delete]) ==
             :ok

    assert Enum.all?(~w(SELECT INSERT UPDATE DELETE), &privilege/1)
  end

  test "publish! reads the policies back and carries them as the version's content" do
    :ok = Migration.policy!(Owner, table: @table, operation: :read, using: @using)

    version =
      Migration.publish!(Owner,
        tables: [@table],
        version: 20_260_909_000_001,
        author: "turnstile_postgres",
        approval: "the conformance suite"
      )

    assert %PolicyVersion{adapter: Turnstile.Postgres, version: "20260909000001"} = version
    assert version.content == Catalog.to_text(policies())
    assert version.content =~ "#{@table} turnstile_scope_read select"
    assert %DateTime{} = version.at
  end

  test "reload! reads the policies a migration wrote after the catalog was loaded" do
    binding = probe_binding()
    loaded = Catalog.load!(binding)
    refute Enum.any?(loaded.policies, &(&1.name == "turnstile_scope_reloaded"))

    on_exit(fn -> Owner.query!("DROP POLICY IF EXISTS turnstile_scope_reloaded ON #{@probe}") end)
    :ok = Migration.policy!(Owner, table: @probe, operation: :reloaded, using: "true")

    assert Catalog.load!(binding) == loaded
    assert Enum.any?(Catalog.reload!(binding).policies, &(&1.name == "turnstile_scope_reloaded"))

    Owner.query!("DROP POLICY turnstile_scope_reloaded ON #{@probe}")
    assert Catalog.reload!(binding) == loaded
  end

  test "a name that is not a plain identifier never reaches a statement" do
    assert %Error.Invalid{what: :table} = catch_error(Migration.protect!(Owner, "rows; DROP TABLE #{@table}"))
    assert %Error.Invalid{what: :role} = catch_error(Migration.grant!(Owner, table: @table, to: "a b", commands: []))
  end

  defp policies, do: Catalog.policies!(Owner, [@table])

  defp expression(policy), do: policy.using || policy.with_check

  defp probe_binding do
    {:ok, binding} = Binding.new(repo: Owner, schemas: [Probe.Row])
    binding
  end

  defp security do
    %{rows: [row]} =
      Owner.query!("SELECT relrowsecurity, relforcerowsecurity FROM pg_class WHERE relname = $1", [
        @table
      ])

    row
  end

  defp privilege(command) do
    %{rows: [[granted]]} = Owner.query!("SELECT has_table_privilege('turnstile_app', $1, $2)", [@table, command])
    granted
  end
end
