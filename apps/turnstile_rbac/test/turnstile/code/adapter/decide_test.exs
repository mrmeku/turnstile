defmodule Turnstile.Code.DecideTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.World
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  defmodule Broken do
    @moduledoc false
    @spec garbage(Turnstile.subject(), Turnstile.environment()) :: term()
    def garbage(_subject, _environment), do: :not_a_dynamic
  end

  defmodule BrokenPolicy do
    @moduledoc false
    use Turnstile.Code.Policy

    role :reader, [:read]

    object Folder do
      predicate :garbage, &Broken.garbage/2
    end
  end

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = Turnstile.Test.with_config(adapter: Turnstile.Code)
    :ok = Binding.override(policy: Roles, repo: Sandboxed)

    world =
      Map.put(
        %World{accounts: %{"ann" => World.cleared(), "bob" => nil}, folders: [1, 2], items: %{10 => 1}},
        :memberships,
        %{{"ann", 1} => :reader, {"bob", 1} => :editor}
      )

    :ok = World.insert(Sandboxed, world)
    environment = %{now: DateTime.utc_now()}
    {:ok, environment: environment, ann: {:user, "ann"}, bob: {:user, "bob"}}
  end

  test "explain names the clauses that held and the reason names the grant or the failing predicate", ctx do
    folder = {:folder, 1}

    allowed = %{rule: "membership", matched: [:membership, :cleared]}

    assert {:ok, %Answer{verdict: :allow, reason: :allowed, meta: ^allowed}} =
             Turnstile.Code.explain(ctx.ann, :read, folder, ctx.environment, [])

    denied = %{rule: "cleared", matched: [:membership]}

    assert {:ok, %Answer{verdict: :deny, reason: :rule_denied, meta: ^denied}} =
             Turnstile.Code.explain(ctx.bob, :edit, folder, ctx.environment, [])

    assert {:ok, %Answer{reason: :deny_by_default, meta: %{matched: [:cleared]}}} =
             Turnstile.Code.explain(ctx.ann, :edit, folder, ctx.environment, [])

    assert {:ok, %Answer{reason: :deny_by_default, meta: %{matched: []}}} =
             Turnstile.Code.explain(ctx.ann, :read, {:folder, 404}, ctx.environment, [])
  end

  test "an item answers as its folder does, through the grant's on column", ctx do
    item = {:item, 10}
    assert {:ok, %Answer{verdict: :allow}} = Turnstile.Code.check(ctx.ann, :read, item, ctx.environment, [])
    assert {:ok, %Answer{verdict: :deny}} = Turnstile.Code.check(ctx.ann, :edit, item, ctx.environment, [])
  end

  test "an unknown operation and an unknown object type are denied with their reasons", ctx do
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :deny, reason: :unknown_operation}} =
             Turnstile.Code.check(ctx.ann, :delete, folder, ctx.environment, [])

    assert {:ok, %Answer{verdict: :deny, reason: :deny_by_default}} =
             Turnstile.Code.check(ctx.ann, :read, {:document, 1}, ctx.environment, [])

    assert {:ok, {rule, %Answer{verdict: :deny}}} =
             Turnstile.Code.scope(ctx.ann, :delete, :folder, ctx.environment, [])

    assert inspect(rule) == inspect(dynamic([_row], false))
  end

  test "a batch answers every object in order across types in one query per type", ctx do
    objects = [{:item, 10}, {:folder, 2}, {:folder, 1}]

    {answers, queries} =
      Turnstile.Test.queries(Sandboxed, fn ->
        {:ok, answers} = Turnstile.Code.batch(ctx.ann, :read, objects, ctx.environment, [])
        answers
      end)

    assert Enum.map(objects, &answers[&1].verdict) == [:allow, :deny, :allow]
    assert length(queries) == 2
  end

  test "a predicate that returns neither a dynamic nor a boolean is an engine error", ctx do
    :ok = Binding.override(policy: BrokenPolicy)

    assert {:error, %Error{reason: :engine_unreachable, detail: detail}} =
             Turnstile.Code.authorize(ctx.ann, :read, {:folder, 1}, ctx.environment, [])

    assert detail =~ "Turnstile.Code failed during authorize"
    assert detail =~ "predicate garbage returned :not_a_dynamic"
  end
end
