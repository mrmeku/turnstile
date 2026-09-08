defmodule Turnstile.Code.BindingTest do
  use ExUnit.Case, async: false

  alias Turnstile.Code.Binding
  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Error
  alias Turnstile.TestRepos.Committed
  alias Turnstile.TestRepos.Sandboxed

  setup do
    on_exit(fn -> :persistent_term.erase(Binding) end)
  end

  test "an override in the calling process resolves without a boot binding" do
    assert {:error, %Error.Invalid{what: :binding}} = Binding.resolve()
    :ok = Binding.override(policy: Roles, repo: Sandboxed)
    assert Binding.resolve() == {:ok, %Binding{policy: Roles, repo: Sandboxed}}
  end

  test "the boot binding resolves under the calling process's overrides" do
    assert {:ok, %Binding{} = bound} = Binding.bind(policy: Roles, repo: Sandboxed)
    assert Binding.resolve() == {:ok, bound}
    assert Binding.to_keyword(bound) == [policy: Roles, repo: Sandboxed]
    :ok = Binding.override(repo: Committed)
    assert Binding.resolve() == {:ok, %Binding{policy: Roles, repo: Committed}}
    assert Binding.bind!(policy: Roles, repo: Committed) == %Binding{policy: Roles, repo: Committed}
    assert_raise Error.Invalid, fn -> Binding.bind!(policy: Committed, repo: Committed) end
    assert %NimbleOptions{} = Binding.options_schema()
  end

  test "the override is read through the callers chain, so a task sees its caller's binding" do
    :ok = Binding.override(policy: Roles, repo: Sandboxed)
    task = Task.async(fn -> Binding.resolve() end)
    assert Task.await(task) == {:ok, %Binding{policy: Roles, repo: Sandboxed}}
  end

  test "a caller that has exited contributes nothing" do
    {:ok, pid} = Task.start(fn -> :ok end)
    ref = Process.monitor(pid)
    assert_receive {:DOWN, ^ref, :process, ^pid, _reason}
    Process.put(:"$callers", [pid])
    assert {:error, %Error.Invalid{}} = Binding.resolve()
  after
    Process.delete(:"$callers")
  end

  test "a scoped override is restored after the function" do
    :ok = Binding.override(policy: Roles, repo: Sandboxed)
    Binding.override([repo: Committed], fn -> assert {:ok, %Binding{repo: Committed}} = Binding.resolve() end)
    assert {:ok, %Binding{repo: Sandboxed}} = Binding.resolve()
  end

  test "a policy that did not use Turnstile.Code.Policy is invalid" do
    assert {:error, %Error.Invalid{detail: detail}} = Binding.new(policy: Sandboxed, repo: Sandboxed)
    assert detail =~ "did not use Turnstile.Code.Policy"
    assert {:error, %Error.Invalid{detail: detail}} = Binding.new(repo: Sandboxed)
    assert detail =~ "policy"
  end
end
