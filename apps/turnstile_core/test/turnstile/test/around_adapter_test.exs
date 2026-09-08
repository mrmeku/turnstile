defmodule Turnstile.Test.AroundAdapterTest do
  use ExUnit.Case, async: true

  alias Turnstile.Adapter.Fake
  alias Turnstile.Environment
  alias Turnstile.Object
  alias Turnstile.Subject
  alias Turnstile.Test.AroundAdapter

  @subject %Subject{id: "11111111-1111-1111-1111-111111111111", kind: :user}
  @object %Object{type: :thing, id: "22222222-2222-2222-2222-222222222222"}
  @environment %Environment{now: ~U[2026-09-08 00:00:00Z]}

  test "every callback but around_query answers as the fake adapter does" do
    assert AroundAdapter.options_schema() == Fake.options_schema()
    assert AroundAdapter.requires_ledger() == Fake.requires_ledger()
    assert AroundAdapter.scope_cap() == Fake.scope_cap()
    args = [@subject, :read, @object, @environment, [verdict: :allow]]
    assert apply(AroundAdapter, :authorize, args) == apply(Fake, :authorize, args)
    assert apply(AroundAdapter, :check, args) == apply(Fake, :check, args)
    batch_args = [@subject, :read, [@object], @environment, []]
    assert apply(AroundAdapter, :batch, batch_args) == apply(Fake, :batch, batch_args)
    scope_args = [@subject, :read, :thing, @environment, []]
    assert apply(AroundAdapter, :scope, scope_args) == apply(Fake, :scope, scope_args)
    assert apply(AroundAdapter, :explain, args) == apply(Fake, :explain, args)
  end

  test "around_query sends the query and the decision to the caller, then runs the call" do
    assert :ran = AroundAdapter.around_query(:the_query, :the_decision, fn -> :ran end)
    assert_received {:around_query, :the_query, :the_decision}
  end
end
