defmodule Turnstile.Cerbos.PlanTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Answer
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Decide
  alias Turnstile.Cerbos.Plan
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Fixture.Item
  alias Turnstile.Fixture.World
  alias Turnstile.Scope
  alias Turnstile.Subject
  alias Turnstile.Test
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  defmodule Declarations do
    @moduledoc false
    use Turnstile.Cerbos.Attributes

    alias Turnstile.Cerbos.Conformance.Memberships
    alias Turnstile.Fixture.Account

    principal :user, schema: Account do
      attribute :clearance, column: :clearance
    end

    resource :folder, schema: Folder do
      attribute :name, column: :name
      attribute :member_roles, subquery: &Memberships.folder_roles_for/1
    end

    resource :item, schema: Item do
      attribute :folder, column: :folder_id
    end

    resource :ghost, schema: Folder do
      attribute :missing, column: :nowhere
    end
  end

  setup tags do
    sidecar = Test.Cerbos.info()
    :ok = Sandbox.setup(Sandboxed, tags)
    :ok = Test.with_config(adapter: {Turnstile.Cerbos, address: sidecar.address}, ledger: :none)

    :ok =
      Binding.override(
        repo: Sandboxed,
        attributes: Declarations,
        policies: sidecar.policies,
        commit: "conformance"
      )

    world = %World{
      accounts: %{"ann" => World.cleared(), "bob" => nil},
      folders: [1, 2],
      items: %{10 => 1},
      memberships: %{{"ann", 1} => :reader}
    }

    :ok = World.insert(Sandboxed, world)
    {:ok, binding} = Binding.resolve()

    {:ok,
     binding: binding,
     address: sidecar.address,
     ann: %Subject{id: "ann", kind: :user},
     bob: %Subject{id: "bob", kind: :user},
     environment: %Environment{now: DateTime.utc_now()}}
  end

  test "a plan that admits every row is every row, and one that admits none is a denial", ctx do
    assert {:ok, rule} = Plan.dynamic(ctx.binding, ctx.ann, :folder, %{"kind" => "KIND_ALWAYS_ALLOWED"})
    assert ids(rule) == [1, 2]
    assert Plan.dynamic(ctx.binding, ctx.ann, :folder, %{"kind" => "KIND_ALWAYS_DENIED"}) == :denied
  end

  test "a comparison on a declared column is a comparison on the row", ctx do
    assert ids(compiled!(ctx, "eq", [attr("name"), value("folder 1")])) == [1]
    assert ids(compiled!(ctx, "ne", [attr("name"), value("folder 1")])) == [2]
    assert ids(compiled!(ctx, "in", [attr("name"), value(["folder 1", "folder 2"])])) == [1, 2]
  end

  test "an ordering reads the row's identifier, and the sides swap with the operator", ctx do
    assert ids(compiled!(ctx, "gt", [id_of(), value(1)])) == [2]
    assert ids(compiled!(ctx, "ge", [id_of(), value(2)])) == [2]
    assert ids(compiled!(ctx, "lt", [id_of(), value(2)])) == [1]
    assert ids(compiled!(ctx, "le", [id_of(), value(1)])) == [1]
    assert ids(compiled!(ctx, "lt", [value(1), id_of()])) == [2]
    assert ids(compiled!(ctx, "ge", [value(1), id_of()])) == [1]
  end

  test "a comparison with nothing is a null test, and an ordering against nothing is no rule", ctx do
    Sandboxed.insert!(%Item{id: 11, title: "item 11"}, turnstile: World.exemption())

    assert items(ctx, "eq", [attr("folder"), value(nil)]) == [11]
    assert items(ctx, "ne", [attr("folder"), value(nil)]) == [10]

    filter = conditional(expression("gt", [attr("folder"), value(nil)]))

    assert Plan.dynamic(ctx.binding, ctx.ann, :item, filter) ==
             {:error, "the plan compares gt with nothing, which reads as no rule over the rows"}
  end

  test "a value the subject's subquery selected is membership in the rows it selected", ctx do
    assert ids(compiled!(ctx, "in", [value("reader"), attr("member_roles")])) == [1]
    assert ids(compiled!(ctx, "in", [value("editor"), attr("member_roles")])) == []
  end

  test "and, or, and not join what their operands compile to", ctx do
    one = expression("eq", [attr("name"), value("folder 1")])
    two = expression("eq", [id_of(), value(2)])

    assert ids(compiled!(ctx, "or", [operand(one), operand(two)])) == [1, 2]
    assert ids(compiled!(ctx, "and", [operand(one), operand(two)])) == []
    assert ids(compiled!(ctx, "not", [operand(one)])) == [2]
  end

  test "a kind the declarations do not name has no schema to compile against", ctx do
    assert Plan.dynamic(ctx.binding, ctx.ann, :nothing, conditional(expression("eq", [id_of(), value(1)]))) ==
             {:error, "the declarations name no schema with one primary key for nothing"}
  end

  test "a plan this adapter does not read is an error rather than a query", ctx do
    assert {:error, detail} = Plan.dynamic(ctx.binding, ctx.ann, :folder, %{"kind" => "KIND_UNSPECIFIED"})
    assert detail =~ "the plan carries no filter this adapter reads"

    assert {:error, no_expression} =
             Plan.dynamic(ctx.binding, ctx.ann, :folder, %{"kind" => "KIND_CONDITIONAL", "condition" => %{}})

    assert no_expression =~ "the plan carries an operand this adapter reads as no expression"

    assert {:error, empty} = compiled(ctx, "and", [])
    assert empty == "the plan uses and with no operands"

    assert {:error, unsupported} = compiled(ctx, "like", [attr("name"), value("folder%")])
    assert unsupported =~ "the plan uses the operator like, which this adapter does not express"
  end

  test "a plan that reads what the declarations do not name is an error", ctx do
    assert {:error, undeclared} = compiled(ctx, "eq", [attr("title"), value("a")])
    assert undeclared =~ "the plan reads the attribute title, which the declarations do not name"

    assert {:error, elsewhere} = compiled(ctx, "eq", [%{"variable" => "request.principal.attr.clearance"}, value("a")])
    assert elsewhere =~ "the plan reads request.principal.attr.clearance, which is no resource attribute"
  end

  test "a plan whose sides this adapter cannot place is an error", ctx do
    assert {:error, both} = compiled(ctx, "eq", [value(1), value(2)])
    assert both == "the plan compares eq between two sides this adapter cannot place"

    nested = operand(expression("size", [attr("member_roles")]))
    assert {:error, unplaceable} = compiled(ctx, "gt", [nested, value(1)])
    assert unplaceable =~ "the plan compares against"

    assert {:error, over_subquery} = compiled(ctx, "eq", [attr("member_roles"), value(1)])
    assert over_subquery =~ "the plan uses eq over a subquery attribute and 1"
  end

  test "a value the column cannot hold and a column the schema does not hold are errors", ctx do
    assert {:error, cast} = compiled(ctx, "eq", [attr("name"), value(1)])
    assert cast =~ "the plan compares name with 1, which the column cannot hold"

    assert {:error, in_cast} = compiled(ctx, "in", [attr("name"), value([1])])
    assert in_cast =~ "the plan compares name with 1, which the column cannot hold"

    filter = conditional(expression("eq", [%{"variable" => "request.resource.attr.missing"}, value("a")]))
    assert {:error, absent} = Plan.dynamic(ctx.binding, ctx.ann, :ghost, filter)
    assert absent =~ "the plan reads nowhere, which Turnstile.Fixture.Folder does not hold"
  end

  test "a scope the sidecar denies outright is a denial with the rule that admits no row", ctx do
    assert {:ok, %Scope{} = scope} = Decide.scoped(ctx.binding, ctx.address, ctx.bob, :read, :folder)
    assert %Answer{verdict: :deny} = scope.answer
    assert scope.answer.policy_version == "conformance"
    assert ids(scope.rule) == []
  end

  test "a plan this adapter cannot express emits the fallback event and fails", ctx do
    :telemetry.attach(inspect(self()), Decide.fallback_event(), &__MODULE__.forward/4, self())

    assert {:error, %Error.Engine{} = error} =
             Turnstile.Cerbos.scope(ctx.ann, :share, :folder, ctx.environment, address: ctx.address)

    assert error.adapter == Turnstile.Cerbos
    assert error.operation == :scope
    assert error.detail =~ "the plan compares against"

    assert_receive {:scope_fallback, %{operation: :share, kind: :folder, detail: detail}}
    assert detail == error.detail
  after
    :telemetry.detach(inspect(self()))
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, _measurements, metadata, pid) do
    send(pid, {:scope_fallback, metadata})
    :ok
  end

  defp compiled!(ctx, operator, operands) do
    {:ok, rule} = compiled(ctx, operator, operands)
    rule
  end

  defp compiled(ctx, operator, operands) do
    Plan.dynamic(ctx.binding, ctx.ann, :folder, conditional(expression(operator, operands)))
  end

  defp conditional(expression), do: %{"kind" => "KIND_CONDITIONAL", "condition" => %{"expression" => expression}}
  defp expression(operator, operands), do: %{"operator" => operator, "operands" => operands}
  defp operand(expression), do: %{"expression" => expression}
  defp attr(name), do: %{"variable" => "request.resource.attr." <> name}
  defp id_of, do: %{"variable" => "request.resource.id"}
  defp value(value), do: %{"value" => value}

  defp items(ctx, operator, operands) do
    filter = conditional(expression(operator, operands))
    {:ok, rule} = Plan.dynamic(ctx.binding, ctx.ann, :item, filter)
    query = from(i in Item, where: ^rule, select: i.id, order_by: i.id)
    Sandboxed.all(query, turnstile: World.exemption())
  end

  defp ids(rule) do
    query = from(f in Folder, where: ^rule, select: f.id, order_by: f.id)
    Sandboxed.all(query, turnstile: World.exemption())
  end
end
