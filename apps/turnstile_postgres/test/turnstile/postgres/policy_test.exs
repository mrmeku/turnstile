defmodule Turnstile.Postgres.PolicyTest do
  use ExUnit.Case, async: true

  alias Turnstile.Error
  alias Turnstile.Postgres.Policy

  test "the adapter's two names are told apart from a policy someone else wrote" do
    scope = policy(Policy.scope_name("read"))
    gate = policy(Policy.gate_name("change_marking"))

    assert Policy.kind(scope) == {:scope, "read"}
    assert Policy.kind(gate) == {:gate, "change_marking"}
    assert Policy.kind(policy("tenant_isolation")) == :other
    assert Policy.kind(policy("turnstile_scope_")) == :other
  end

  test "the command letter pg_policy carries becomes the command" do
    assert Enum.map(~w[* r a w d], &Policy.command/1) == [:all, :select, :insert, :update, :delete]
  end

  test "the text a policy version carries names the table, the policy, and both expressions" do
    text = Policy.to_text(%{policy("turnstile_scope_read") | using: "true", with_check: nil})
    assert text == "folders turnstile_scope_read select\n  USING true\n  WITH CHECK -\n"
  end

  test "the text of a version reads back as the policies it carries, expressions and all" do
    policies = [
      %{
        policy("turnstile_scope_read")
        | using: "(EXISTS ( SELECT 1\n   FROM public.office_roles\n  WHERE (role = 'designator'::text)))"
      },
      %{
        policy("turnstile_gate_change_marking")
        | command: :update,
          using: "true",
          with_check: "(now() > '2026-01-01'::date)"
      },
      %{policy("tenant_isolation") | command: :all}
    ]

    text = Enum.map_join(policies, &Policy.to_text/1)

    assert Policy.from_text(text) == policies
  end

  test "a version with no policies in it reads back as no policies" do
    assert Policy.from_text("") == []
    assert Policy.from_text("\n\n") == []
  end

  test "the statement that writes a policy names the command and only the clauses it has" do
    scope = %{policy("turnstile_scope_read") | using: "true"}
    gate = %{policy("turnstile_gate_decontrol") | command: :update, using: "a", with_check: "b"}

    assert Policy.to_sql(scope) == "CREATE POLICY turnstile_scope_read ON folders FOR SELECT USING (true)"
    assert Policy.to_sql(gate) == "CREATE POLICY turnstile_gate_decontrol ON folders FOR UPDATE USING (a) WITH CHECK (b)"

    assert Policy.to_sql(%{policy("p") | command: :all}) == "CREATE POLICY p ON folders FOR ALL"

    assert Policy.to_sql(%{policy("p") | command: :insert, with_check: "c"}) ==
             "CREATE POLICY p ON folders FOR INSERT WITH CHECK (c)"

    assert Policy.to_sql(%{policy("p") | command: :delete, using: "d"}) ==
             "CREATE POLICY p ON folders FOR DELETE USING (d)"
  end

  test "a name the statement cannot quote is refused rather than written" do
    assert_raise Error.Invalid, ~r/invalid policy/, fn -> Policy.to_sql(%{policy(~s(a"b)) | using: "true"}) end
    assert_raise Error.Invalid, ~r/invalid table/, fn -> Policy.to_sql(%{policy("p") | table: "Folders"}) end
  end

  defp policy(name) do
    %Policy{name: name, table: "folders", command: :select, using: nil, with_check: nil}
  end
end
