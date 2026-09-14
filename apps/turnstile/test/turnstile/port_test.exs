defmodule Turnstile.PortTest do
  use ExUnit.Case, async: true

  alias Ecto.Query.DynamicExpr
  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Port
  alias Turnstile.Test.Fake

  defmodule Explaining do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def options_schema do
      NimbleOptions.new!(
        verdict: [type: {:in, [:allow, :deny]}, default: :deny],
        reachable?: [type: :boolean, default: true]
      )
    end

    @impl Turnstile.Adapter
    def scope_cap, do: :none

    @impl Turnstile.Adapter
    def authorize(subject, operation, object, environment, options),
      do: Fake.authorize(subject, operation, object, environment, options)

    @impl Turnstile.Adapter
    def check(subject, operation, object, environment, options),
      do: Fake.check(subject, operation, object, environment, options)

    @impl Turnstile.Adapter
    def batch(subject, operation, objects, environment, options),
      do: Fake.batch(subject, operation, objects, environment, options)

    @impl Turnstile.Adapter
    def scope(subject, operation, type, environment, options),
      do: Fake.scope(subject, operation, type, environment, options)

    @impl Turnstile.Adapter
    def explain(_subject, _operation, _object, _environment, options) do
      if options[:reachable?] do
        answer = Fake.answer(options)
        {:ok, %{answer | meta: Map.put(answer.meta, :matched, ["rule one"])}}
      else
        {:error, %Error{reason: :engine_unreachable, detail: "#{inspect(__MODULE__)} is out of reach"}}
      end
    end
  end

  defmodule Silent do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def scope_cap, do: :none

    @impl Turnstile.Adapter
    def authorize(subject, operation, object, environment, options),
      do: Fake.authorize(subject, operation, object, environment, options)

    @impl Turnstile.Adapter
    def check(subject, operation, object, environment, options),
      do: Fake.check(subject, operation, object, environment, options)

    @impl Turnstile.Adapter
    def batch(subject, operation, objects, environment, options),
      do: Fake.batch(subject, operation, objects, environment, options)

    @impl Turnstile.Adapter
    def scope(subject, operation, type, environment, options),
      do: Fake.scope(subject, operation, type, environment, options)
  end

  defmodule Raising do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def scope_cap, do: :none

    @impl Turnstile.Adapter
    def authorize(_subject, _operation, _object, _environment, _options), do: raise("the decider broke")

    @impl Turnstile.Adapter
    def check(_subject, _operation, _object, _environment, _options), do: raise("the decider broke")

    @impl Turnstile.Adapter
    def batch(_subject, _operation, _objects, _environment, _options), do: raise("the decider broke")

    @impl Turnstile.Adapter
    def scope(_subject, _operation, _type, _environment, _options), do: raise("the decider broke")
  end

  @user {:user, "acct-a"}
  @service {:non_person_entity, "svc-a"}
  @robot {:robot, "r2"}
  @folder {:folder, 1}
  @other {:folder, 2}

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

    assert Port.batch(@robot, :read, [@folder], []) == %{{:folder, 1} => :deny}
    assert Port.filter(@robot, :read, [@folder], []) == []
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
               "(#{inspect(Fake)} failed during authorize: engine down)"
  end

  test "batch and filter publish one event for the objects they were asked about" do
    assert Port.batch(@user, :read, [@folder, @other], []) == %{{:folder, 1} => :allow, {:folder, 2} => :deny}
    assert_received {[:turnstile, :decision], _ref, _measurements, %{verdict: :deny, object: {:folder, nil}}}
    assert Port.filter(@user, :read, [@other, @folder], []) == [@folder]
    assert Port.filter(@user, :read, [], []) == []
    assert_received {[:turnstile, :decision], _ref, _measurements, %{object: {nil, nil}}}
  end

  test "a narrowing call publishes the rule in the object's place" do
    assert {_rule, %Decision{verdict: :scoped}} = Port.scope(@user, :read, :folder, [])
    assert_received {[:turnstile, :decision], _ref, _measurements, %{verdict: :scoped, object: rule}}
    assert %DynamicExpr{} = rule
  end

  test "a decider that raises denies closed, and its event carries the exception" do
    :ok = Turnstile.Test.with_config(adapter: Raising)

    assert {:error, %Error{reason: :engine_unreachable} = error} = Port.authorize(@user, :read, @folder, [])
    assert Exception.message(error) =~ "#{inspect(Raising)} raised during authorize: the decider broke"

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{exception: %RuntimeError{}, verdict: :deny, reason: :engine_unreachable}}

    assert Port.check(@user, :read, @folder, []) == false
    assert Port.batch(@user, :read, [@folder], []) == %{@folder => :deny}
    assert {_rule, %Decision{verdict: :deny, reason: :engine_unreachable}} = Port.scope(@user, :read, :folder, [])

    assert_received {[:turnstile, :decision], _ref, _measurements,
                     %{exception: %RuntimeError{}, object: {:folder, nil}, reason: :engine_unreachable}}
  end

  test "review answers a rule per subject over a type and allowed references over a population" do
    reviewed = Port.review(@user, [@user, @service, @robot], :read, :folder, [])
    assert map_size(reviewed) == 3
    assert Enum.all?(reviewed, fn {_subject, rule} -> match?(%DynamicExpr{}, rule) end)
    assert_received {[:turnstile, :decision], _ref, _measurements, %{verdict: :scoped, object: {:folder, nil}}}

    assert Port.review(@user, [@user, @robot], :read, [@folder, @other], []) ==
             %{@user => [{:folder, 1}], @robot => []}

    assert Port.review(@user, [@user], :read, [], []) == %{@user => []}
  end

  test "explain answers unsupported from an adapter that says so or defines no explain" do
    assert {:error, %Error{reason: :unsupported, detail: named}} = Port.explain(@user, :read, @folder, [])
    assert named =~ "does not support explain"
    :ok = Turnstile.Test.with_config(adapter: Silent)
    assert {:error, %Error{reason: :unsupported, detail: detail}} = Port.explain(@user, :read, @folder, [])
    assert detail =~ "Silent does not support explain/5"
  end

  test "explain returns the answer with what matched and a decision, denied closed when it cannot reach" do
    :ok = Turnstile.Test.with_config(adapter: {Explaining, verdict: :allow})

    assert {:ok, %Answer{meta: %{matched: ["rule one"]}}, %Decision{verdict: :allow, adapter: Explaining}} =
             Port.explain(@user, :read, @folder, [])

    :ok = Turnstile.Test.with_config(adapter: {Explaining, reachable?: false})

    assert {:ok, %Answer{verdict: :deny, reason: :engine_unreachable}, %Decision{verdict: :deny}} =
             Port.explain(@user, :read, @folder, [])
  end

  test "the operation id given is the one every record of the call carries" do
    id = Turnstile.Id.new()
    assert {:ok, %Decision{operation_id: ^id}} = Port.authorize(@user, :read, @folder, operation_id: id)
    assert_received {[:turnstile, :decision], _ref, _measurements, %{operation_id: ^id}}
    assert_raise NimbleOptions.ValidationError, fn -> Port.check(@user, :read, @folder, operation_id: 1) end
  end
end
