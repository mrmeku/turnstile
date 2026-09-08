defmodule Turnstile.PortTest do
  use ExUnit.Case, async: true

  alias Turnstile.Adapter.Fake
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Object
  alias Turnstile.Port
  alias Turnstile.Subject

  defmodule DownLedger do
    @moduledoc false
    @behaviour Turnstile.Ledger

    @impl Turnstile.Ledger
    def options_schema, do: NimbleOptions.new!([])

    @impl Turnstile.Ledger
    def append(_options, _events), do: {:error, down(:append)}

    @impl Turnstile.Ledger
    def read(_options, _from, _limit), do: {:error, down(:read)}

    @impl Turnstile.Ledger
    def head(_options), do: {:error, down(:head)}

    defp down(operation), do: %Error.Engine{adapter: __MODULE__, operation: operation, detail: "ledger down"}
  end

  defmodule Explaining do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def options_schema, do: Fake.options_schema()

    @impl Turnstile.Adapter
    def requires_ledger, do: false

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
      {:ok, %Explanation{answer: Fake.answer(options), matched: ["rule one"]}}
    end
  end

  defmodule Silent do
    @moduledoc false
    @behaviour Turnstile.Adapter

    @impl Turnstile.Adapter
    def requires_ledger, do: false

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

  @user %Subject{id: "acct-a", kind: :user}
  @service %Subject{id: "svc-a", kind: :non_person_entity}
  @robot %Subject{id: "r2", kind: :robot}
  @folder %Object{type: :folder, id: 1}
  @other %Object{type: :folder, id: 2}

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})
    :ok = Turnstile.Test.with_config(adapter: {Fake, rules: rules}, ledger: :none)
    handler = :telemetry_test.attach_event_handlers(self(), Port.events())
    on_exit(fn -> :telemetry.detach(handler) end)
    {:ok, rules: rules}
  end

  test "events/0 names a span per subject kind and one for unknown kinds" do
    assert [:turnstile, :user, :start] in Port.events()
    assert [:turnstile, :unknown, :exception] in Port.events()
    assert length(Port.events()) == 12
  end

  test "a call is one span named for the subject's kind, carrying the decision at stop" do
    assert {:ok, %Decision{verdict: :allow, head_position: nil}} = Port.authorize(@user, :read, @folder, [])
    assert_received {[:turnstile, :user, :start], _ref, _measurements, %{subject_kind: :user, object: {:folder, 1}}}
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{decision: %{verdict: "allow"}}}

    assert Port.check(@service, :read, @folder, []) == false
    assert_received {[:turnstile, :non_person_entity, :stop], _ref, _measurements, %{decision: %{verdict: "deny"}}}
  end

  test "an unknown subject kind is denied before the adapter is asked, under the unknown span" do
    assert {:error, %Error.NotAuthorized{reason: %{code: :unknown_subject_kind}}} =
             Port.authorize(@robot, :read, @folder, [])

    assert Port.batch(@robot, :read, [@folder], []) == %{{:folder, 1} => :deny}
    assert Port.filter(@robot, :read, [@folder], []) == []
    assert {_rule, %Decision{verdict: :deny}} = Port.scope(@robot, :read, :folder, [])

    assert_received {[:turnstile, :unknown, :stop], _ref, _measurements,
                     %{decision: %{reason: %{code: "deny_by_default"}}}}
  end

  test "an unreachable ledger head fails every call closed with engine_unreachable" do
    :ok = Turnstile.Test.with_config(ledger: {DownLedger, []})
    assert Port.check(@user, :read, @folder, []) == false

    assert {:error, %Error.NotAuthorized{reason: %{code: :engine_unreachable}}} =
             Port.authorize(@user, :read, @folder, [])

    assert Port.batch(@user, :read, [@folder], []) == %{{:folder, 1} => :deny}
    assert {_rule, %Decision{verdict: :deny, head_position: nil}} = Port.scope(@user, :read, :folder, [])
    assert_received {[:turnstile, :user, :start], _ref, _measurements, %{head_position: nil}}
  end

  test "an engine error from the adapter denies with the detail as the reason", %{rules: rules} do
    :ok = Fake.fail(rules, "engine down")

    assert {:error, %Error.NotAuthorized{reason: %{code: :engine_unreachable, message: message}}} =
             Port.authorize(@user, :read, @folder, [])

    assert message =~ "engine down"
  end

  test "batch and filter share one record listing verdicts per object and the ids in order" do
    assert Port.batch(@user, :read, [@folder, @other], []) == %{{:folder, 1} => :allow, {:folder, 2} => :deny}
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{ids: [1, 2], verdicts: verdicts}}
    assert verdicts == %{{:folder, 1} => :allow, {:folder, 2} => :deny}
    assert Port.filter(@user, :read, [@other, @folder], []) == [@folder]
    assert Port.filter(@user, :read, [], []) == []
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{decision: %{verdict: "deny", object: %{id: nil}}}}
  end

  test "ids past the batch cap become a count and a hash" do
    :ok = Turnstile.Test.with_config(caps: [batch_ids: 2])
    objects = for id <- 1..3, do: %Object{type: :folder, id: id}
    assert map_size(Port.batch(@user, :read, objects, [])) == 3
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{ids: %{count: 3, sha256: hash}}}
    assert String.length(hash) == 64
  end

  test "scope records the rule, truncated past the cap with a hash of the whole" do
    assert {_rule, %Decision{verdict: :scoped}} = Port.scope(@user, :read, :folder, [])
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{rule: %{truncated: false, text: text}}}
    assert text =~ "dynamic"

    :ok = Turnstile.Test.with_config(caps: [rule_bytes: 8])
    assert {_rule, %Decision{verdict: :scoped}} = Port.scope(@user, :read, :folder, [])
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{rule: %{truncated: true, text: short}}}
    assert byte_size(short) == 8
  end

  test "review answers a rule per subject over a type and allowed references over a population" do
    reviewed = Port.review(@user, [@user, @service, @robot], :read, :folder, [])
    assert map_size(reviewed) == 3
    assert Enum.all?(reviewed, fn {_subject, rule} -> match?(%Ecto.Query.DynamicExpr{}, rule) end)
    assert_received {[:turnstile, :user, :stop], _ref, _measurements, %{decision: %{verdict: "scoped"}, reviewed: out}}
    assert is_binary(out[{:user, "acct-a"}])

    assert Port.review(@user, [@user, @robot], :read, [@folder, @other], []) ==
             %{@user => [{:folder, 1}], @robot => []}

    assert Port.review(@user, [@user], :read, [], []) == %{@user => []}
  end

  test "explain answers unsupported from an adapter that says so or defines no explain" do
    assert {:error, %Error.Unsupported{feature: :explain}} = Port.explain(@user, :read, @folder, [])
    :ok = Turnstile.Test.with_config(adapter: Silent)
    assert {:error, %Error.Unsupported{adapter: Silent, note: note}} = Port.explain(@user, :read, @folder, [])
    assert note =~ "explain/5"
  end

  test "explain returns the explanation and a decision where the adapter can say, denied closed when it cannot reach" do
    :ok = Turnstile.Test.with_config(adapter: {Explaining, verdict: :allow})

    assert {:ok, %Explanation{matched: ["rule one"]}, %Decision{verdict: :allow, adapter: Explaining}} =
             Port.explain(@user, :read, @folder, [])

    :ok = Turnstile.Test.with_config(ledger: {DownLedger, []})

    assert {:ok, %Explanation{matched: [], answer: %{verdict: :deny}}, %Decision{verdict: :deny}} =
             Port.explain(@user, :read, @folder, [])
  end

  test "the operation id given is the one every record of the call carries" do
    id = Turnstile.Id.new()
    assert {:ok, %Decision{operation_id: ^id}} = Port.authorize(@user, :read, @folder, operation_id: id)
    assert_received {[:turnstile, :user, :start], _ref, _measurements, %{operation_id: ^id}}
    assert_raise NimbleOptions.ValidationError, fn -> Port.check(@user, :read, @folder, operation_id: 1) end
  end
end
