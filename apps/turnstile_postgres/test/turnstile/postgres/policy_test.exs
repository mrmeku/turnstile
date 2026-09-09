defmodule Turnstile.Postgres.PolicyTest do
  use ExUnit.Case, async: true

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

  defp policy(name) do
    %Policy{name: name, table: "folders", command: :select, using: nil, with_check: nil}
  end
end
