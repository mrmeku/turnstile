defmodule Turnstile.PortTest do
  use ExUnit.Case, async: true

  alias Ecto.Query.DynamicExpr
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Port
  alias Turnstile.Test.Fake

  defmodule Raising do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def scope_cap, do: :none

    @impl Turnstile.Adapter
    def decide(_subject, _operation, _object, _environment, _options), do: raise("the decider broke")

    @impl Turnstile.Adapter
    def scope(_subject, _operation, _type, _environment, _options), do: raise("the decider broke")
  end

  @user {:user, "acct-a"}
  @service {:non_person_entity, "svc-a"}
  @robot {:robot, "r2"}
  @folder {:folder, 1}

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules})
    handler = :telemetry_test.attach_event_handlers(self(), [Port.event()])
    on_exit(fn -> :telemetry.detach(handler) end)
    {:ok, rules: rules}
  end

  test "a call publishes one decision event carrying who asked, what was answered, and how long it took" do
    assert {:ok, %Decision{verdict: :allow}} = Port.authorize(@user, :read, @folder, [])

    assert_received {[:turnstile, :decision], _ref, %{duration: duration}, metadata}
    assert duration >= 0
    assert metadata.subject == @user
    assert metadata.subject_kind == :user
    assert metadata.operation == :read
    assert metadata.object == {:folder, 1}
    assert metadata.verdict == :allow
    assert metadata.reason == :allowed
    assert metadata.decider == Fake
    assert metadata.env == %{}
    assert metadata.exception == nil
    assert %DateTime{} = metadata.time
    assert is_binary(metadata.operation_id)

    assert Port.check(@service, :read, @folder, env: %{shift: :night}) == false
    assert_received {[:turnstile, :decision], _ref, _measurements, %{verdict: :deny, subject_kind: :non_person_entity}}
  end

  test "an unknown subject kind is denied before the adapter is asked, and its event says so" do
    assert {:error, %Error{reason: :unknown_subject_kind}} =
             Port.authorize(@robot, :read, @folder, [])

    assert {_rule, %Decision{verdict: :deny}} = Port.scope(@robot, :read, :folder, [])

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{subject_kind: :unknown, verdict: :deny, reason: :unknown_subject_kind}}
  end

  test "an engine error from the adapter denies with the detail as the reason", %{rules: rules} do
    :ok = Fake.fail(rules, "engine down")

    assert {:error, %Error{reason: :engine_unreachable} = error} =
             Port.authorize(@user, :read, @folder, [])

    assert Exception.message(error) ==
             "user acct-a may not read {:folder, 1}: engine_unreachable " <>
               "(#{inspect(Fake)} failed during decide: engine down)"
  end

  test "a narrowing call publishes the rule in the object's place" do
    assert {_rule, %Decision{verdict: :scoped}} = Port.scope(@user, :read, :folder, [])
    assert_received {[:turnstile, :decision], _ref, _measurements, %{verdict: :scoped, object: rule}}
    assert %DynamicExpr{} = rule
  end

  test "a decider that raises denies closed, and its event carries the exception" do
    :ok = Turnstile.Test.with_config(adapter: Raising)

    assert {:error, %Error{reason: :engine_unreachable} = error} = Port.authorize(@user, :read, @folder, [])
    assert Exception.message(error) =~ "#{inspect(Raising)} raised during decide: the decider broke"

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{exception: %RuntimeError{}, verdict: :deny, reason: :engine_unreachable}}

    assert Port.check(@user, :read, @folder, []) == false
    assert {_rule, %Decision{verdict: :deny, reason: :engine_unreachable}} = Port.scope(@user, :read, :folder, [])

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{exception: %RuntimeError{}, object: %DynamicExpr{}, reason: :engine_unreachable}}
  end

  test "review answers a rule and a decision per subject over a type, each its own record under one operation id" do
    reviewed = Port.review(@user, [@user, @service, @robot], :read, :folder, [])
    assert map_size(reviewed) == 3
    assert Enum.all?(reviewed, fn {_subject, {rule, %Decision{}}} -> match?(%DynamicExpr{}, rule) end)

    {_rule, %Decision{verdict: :scoped, subject: @user, operation_id: id}} = reviewed[@user]
    assert %Decision{verdict: :deny, subject: @robot, operation_id: ^id} = elem(reviewed[@robot], 1)

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{subject: @user, verdict: :scoped, object: %DynamicExpr{}}}

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{subject: @robot, verdict: :deny, subject_kind: :unknown}}

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{subject: @user, verdict: :scoped, object: {:folder, nil}, operation_id: ^id}}
  end

  test "the operation id given is the one every record of the call carries" do
    id = Turnstile.Id.new()
    assert {:ok, %Decision{operation_id: ^id}} = Port.authorize(@user, :read, @folder, operation_id: id)
    assert_received {[:turnstile, :decision], _ref, _measurements, %{operation_id: ^id}}
    assert_raise NimbleOptions.ValidationError, fn -> Port.check(@user, :read, @folder, operation_id: 1) end
  end
end
