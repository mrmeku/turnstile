defmodule ExampleRbac.PolicyTest do
  use ExUnit.Case, async: true

  alias ExampleRbac.Policy
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Coverage
  alias Turnstile.Config

  test "every fact a rule reads is declared on the schema it reads" do
    assert Coverage.check(Policy) == :ok
    assert Coverage.check(ExampleRbac.Tightened) == :ok
  end

  test "the boot names the adapter, the policy, and the repo" do
    assert {:ok, %Config{} = config} = Config.resolve()
    assert Config.adapter(config) == {Turnstile.Code, []}
    assert {:ok, %Binding{policy: Policy, repo: Example.Repo}} = Binding.resolve()
    assert Turnstile.Code.Version.ref(Policy) == "2026.09.1"
  end

  test "the role table holds the permissions of the reference" do
    assert Turnstile.Code.Policy.roles_for(Policy, :read) == [:member, :lead, :designator, :approver]
    assert Turnstile.Code.Policy.roles_for(Policy, :change_marking) == [:designator]
    assert Turnstile.Code.Policy.roles_for(Policy, :approve_marking) == [:approver]
    assert Turnstile.Code.Policy.roles_for(ExampleRbac.Tightened, :read) == [:lead, :designator, :approver]
  end
end
