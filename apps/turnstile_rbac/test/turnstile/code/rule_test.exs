defmodule Turnstile.Code.RuleTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [where: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Policy
  alias Turnstile.Code.Rule
  alias Turnstile.Environment
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.Membership
  alias Turnstile.Fixture.World
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Subject
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  defmodule Bools do
    @moduledoc false
    import Ecto.Query, only: [dynamic: 2]

    @spec yes(Subject.t(), Environment.t()) :: boolean()
    def yes(_subject, _environment), do: true

    @spec no(Subject.t(), Environment.t()) :: boolean()
    def no(_subject, _environment), do: false

    @spec named() :: Ecto.Query.dynamic_expr()
    def named, do: dynamic([folder], folder.name != "closed")
  end

  defmodule FixedRole do
    @moduledoc false
    use Policy, version: "fixed"

    role :reader, [:read]
    role :editor, [:read, :edit]

    object Folder do
      grant :any_membership, Membership, as: :reader
      predicate :yes, &Bools.yes/2
    end
  end

  defmodule NamedRole do
    @moduledoc false
    use Policy, version: "named"

    role :reader, [:read]
    role :editor, [:read]

    object Folder do
      grant :membership, Membership, role: :role, on: :id
      predicate :no, &Bools.no/2
    end
  end

  defmodule Hopped do
    @moduledoc false
    use Policy, version: "hopped"

    role :reader, [:read]
    role :editor, [:read, :edit]

    object Item do
      grant :folder_membership, Membership, on: :folder_id, through: [{Folder, :id, where: &Bools.named/0}]
      predicate :no, &Bools.no/2, only: [:edit]
    end
  end

  defmodule Composite do
    @moduledoc false
    use Ecto.Schema

    @primary_key false
    schema "turnstile_rule_test_composite" do
      field(:left, :integer, primary_key: true)
      field(:right, :integer, primary_key: true)
    end
  end

  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = Turnstile.Test.with_config(adapter: Turnstile.Code, ledger: :none)

    world = %World{
      accounts: %{"ann" => World.cleared()},
      folders: [1],
      items: %{1 => 1},
      memberships: %{{"ann", 1} => :editor}
    }

    :ok = World.insert(Sandboxed, world)
    {:ok, environment: %Environment{now: DateTime.utc_now()}, ann: %Subject{id: "ann", kind: :user}}
  end

  test "a grant with a fixed role holds through any membership row when the role permits the operation", ctx do
    :ok = Binding.override(policy: FixedRole, repo: Sandboxed)
    folder = %Object{type: :folder, id: 1}

    assert {:ok, %Answer{verdict: :allow, reason: reason}} =
             Turnstile.Code.check(ctx.ann, :read, folder, ctx.environment, [])

    assert reason == Reason.allowed("any_membership")

    assert {:ok, %Answer{verdict: :deny, reason: %Reason{code: :deny_by_default}}} =
             Turnstile.Code.check(ctx.ann, :edit, folder, ctx.environment, [])
  end

  test "a named role column and a boolean predicate", ctx do
    :ok = Binding.override(policy: NamedRole, repo: Sandboxed)
    folder = %Object{type: :folder, id: 1}

    assert {:ok, %Answer{verdict: :deny, reason: reason}} =
             Turnstile.Code.check(ctx.ann, :read, folder, ctx.environment, [])

    assert reason == Reason.rule_denied("no")
    assert {:ok, %Rule{predicates: [no: expression]}} = Rule.build(NamedRole, ctx.ann, :read, :folder, ctx.environment)
    assert %Ecto.Query.DynamicExpr{} = expression
  end

  test "a grant reaches the row through a hop, the hop's filter narrows it, and a predicate applies only to its operations",
       ctx do
    :ok = Binding.override(policy: Hopped, repo: Sandboxed)
    item = %Object{type: :item, id: 1}

    assert {:ok, %Answer{verdict: :allow, reason: reason}} =
             Turnstile.Code.check(ctx.ann, :read, item, ctx.environment, [])

    assert reason == Reason.allowed("folder_membership")

    assert {:ok, %Answer{verdict: :deny, reason: %Reason{code: :rule_denied}}} =
             Turnstile.Code.check(ctx.ann, :edit, item, ctx.environment, [])

    closed = where(Folder, id: 1)
    {1, nil} = Sandboxed.update_all(closed, [set: [name: "closed"]], turnstile: World.exemption())

    assert {:ok, %Answer{verdict: :deny, reason: %Reason{code: :deny_by_default}}} =
             Turnstile.Code.check(ctx.ann, :read, item, ctx.environment, [])
  end

  test "the scope answer names every clause and the rule needs a one-column primary key", ctx do
    assert {:ok, %Rule{} = rule} = Rule.build(FixedRole, ctx.ann, :read, :folder, ctx.environment)
    assert Rule.answer(rule).reason == Reason.allowed("any_membership, yes")
    clauses = Rule.clauses(rule)
    assert Enum.sort(Map.keys(clauses)) == [:any_membership, :yes]
    assert Rule.primary_key(Folder) == :id
    assert_raise ArgumentError, ~r/has primary key \[:left, :right\]/, fn -> Rule.primary_key(Composite) end
  end
end
