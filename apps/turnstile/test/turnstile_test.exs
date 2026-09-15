defmodule TurnstileTest do
  use ExUnit.Case, async: true

  alias Turnstile.Decision
  alias Turnstile.Test.Fake

  @user {:user, "acct-a"}
  @folder {:folder, 1}

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    :ok
  end

  test "every function delegates to the port with empty options by default" do
    assert {:ok, %Decision{verdict: :allow}} = Turnstile.authorize(@user, :read, @folder)
    assert Turnstile.check(@user, :read, @folder)
    assert {_rule, %Decision{verdict: :scoped}} = Turnstile.scope(@user, :read, :folder)
    assert %{@user => {_rule, %Decision{verdict: :scoped}}} = Turnstile.review(@user, [@user], :read, :folder)
  end
end
