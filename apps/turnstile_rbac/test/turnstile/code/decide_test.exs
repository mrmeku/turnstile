defmodule Turnstile.Code.DecideTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Conformance.Roles
  alias Turnstile.Environment
  alias Turnstile.Error.Engine
  alias Turnstile.Explanation
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.World
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  defmodule Broken do
    @moduledoc false
    @spec garbage(Subject.t(), Environment.t()) :: term()
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
    :ok = Turnstile.Test.with_config(adapter: Turnstile.Code, ledger: :none)
    :ok = Binding.override(policy: Roles, repo: Sandboxed)

    world =
      Map.put(
        %World{accounts: %{"ann" => World.cleared(), "bob" => nil}, folders: [1, 2], items: %{10 => 1}},
        :memberships,
        %{{"ann", 1} => :reader, {"bob", 1} => :editor}
      )

    :ok = World.insert(Sandboxed, world)
    environment = %Environment{now: DateTime.utc_now()}
    {:ok, environment: environment, ann: %Subject{id: "ann", kind: :user}, bob: %Subject{id: "bob", kind: :user}}
  end

  test "explain names the clauses that held and the reason names the grant or the failing predicate", ctx do
    folder = %Object{type: :folder, id: 1}

    assert {:ok, %Explanation{answer: %Answer{verdict: :allow, reason: reason}, matched: [:membership, :cleared]}} =
             Turnstile.Code.explain(ctx.ann, :read, folder, ctx.environment, [])

    assert reason == Reason.allowed("membership")

    assert {:ok, %Explanation{answer: %Answer{verdict: :deny, reason: denied}, matched: [:membership]}} =
             Turnstile.Code.explain(ctx.bob, :edit, folder, ctx.environment, [])

    assert denied == Reason.rule_denied("cleared")

    assert {:ok, %Explanation{answer: %Answer{reason: %Reason{code: :deny_by_default}}, matched: [:cleared]}} =
             Turnstile.Code.explain(ctx.ann, :edit, folder, ctx.environment, [])

    assert {:ok, %Explanation{answer: %Answer{reason: %Reason{code: :deny_by_default}}, matched: []}} =
             Turnstile.Code.explain(ctx.ann, :read, %Object{type: :folder, id: 404}, ctx.environment, [])
  end

  test "an item answers as its folder does, through the grant's on column", ctx do
    item = %Object{type: :item, id: 10}
    assert {:ok, %Answer{verdict: :allow}} = Turnstile.Code.check(ctx.ann, :read, item, ctx.environment, [])
    assert {:ok, %Answer{verdict: :deny}} = Turnstile.Code.check(ctx.ann, :edit, item, ctx.environment, [])
  end

  test "an unknown operation and an unknown object type are denied with their reasons", ctx do
    folder = %Object{type: :folder, id: 1}

    assert {:ok, %Answer{verdict: :deny, reason: %Reason{code: :unknown_operation}}} =
             Turnstile.Code.check(ctx.ann, :delete, folder, ctx.environment, [])

    assert {:ok, %Answer{verdict: :deny, reason: %Reason{code: :deny_by_default}}} =
             Turnstile.Code.check(ctx.ann, :read, %Object{type: :document, id: 1}, ctx.environment, [])

    assert {:ok, %Scope{rule: rule, answer: %Answer{verdict: :deny}}} =
             Turnstile.Code.scope(ctx.ann, :delete, :folder, ctx.environment, [])

    assert inspect(rule) == inspect(dynamic([_row], false))
  end

  test "a batch answers every object in order across types in one query per type", ctx do
    objects = [%Object{type: :item, id: 10}, %Object{type: :folder, id: 2}, %Object{type: :folder, id: 1}]

    {answers, queries} =
      Turnstile.Test.queries(Sandboxed, fn ->
        {:ok, answers} = Turnstile.Code.batch(ctx.ann, :read, objects, ctx.environment, [])
        answers
      end)

    assert Enum.map(objects, &answers[Object.ref(&1)].verdict) == [:allow, :deny, :allow]
    assert length(queries) == 2
  end

  test "a predicate that returns neither a dynamic nor a boolean is an engine error", ctx do
    :ok = Binding.override(policy: BrokenPolicy)

    assert {:error, %Engine{adapter: Turnstile.Code, operation: :authorize, detail: detail}} =
             Turnstile.Code.authorize(ctx.ann, :read, %Object{type: :folder, id: 1}, ctx.environment, [])

    assert detail =~ "predicate garbage returned :not_a_dynamic"
  end
end
