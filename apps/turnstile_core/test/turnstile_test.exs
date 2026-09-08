defmodule TurnstileTest do
  use ExUnit.Case, async: true

  alias Turnstile.Adapter.Fake
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Object
  alias Turnstile.Subject

  @user %Subject{id: "acct-a", kind: :user}
  @folder %Object{type: :folder, id: 1}
  @other %Object{type: :folder, id: 2}

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules}, ledger: :none)
    :ok
  end

  test "every function delegates to the port with empty options by default" do
    assert {:ok, %Decision{verdict: :allow}} = Turnstile.authorize(@user, :read, @folder)
    assert %Decision{verdict: :allow} = Turnstile.authorize!(@user, :read, @folder)
    assert Turnstile.check(@user, :read, @folder)
    assert Turnstile.batch(@user, :read, [@folder, @other]) == %{{:folder, 1} => :allow, {:folder, 2} => :deny}
    assert Turnstile.filter(@user, :read, [@folder, @other]) == [@folder]
    assert {_rule, %Decision{verdict: :scoped}} = Turnstile.scope(@user, :read, :folder)
    assert {:error, %Error.Unsupported{}} = Turnstile.explain(@user, :read, @folder)
    assert %{@user => [{:folder, 1}]} = Turnstile.review(@user, [@user], :read, [@folder, @other])
  end

  test "authorize! raises the not-authorized error on a denial" do
    assert_raise Error.NotAuthorized, fn -> Turnstile.authorize!(@user, :edit, @folder) end
  end
end
