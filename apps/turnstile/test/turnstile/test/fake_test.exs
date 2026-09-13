defmodule Turnstile.Test.FakeTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, where: 2]

  alias Turnstile.Answer
  alias Turnstile.Error
  alias Turnstile.Test.Fake

  @subject {:user, "11111111-1111-1111-1111-111111111111"}
  @object {:thing, "22222222-2222-2222-2222-222222222222"}
  @environment %{now: ~U[2026-09-08 00:00:00Z]}

  test "it denies by default with a deny-by-default reason and the fake policy version" do
    assert {:ok, %Answer{verdict: :deny, reason: :deny_by_default, version: "fake"} = answer} =
             Fake.authorize(@subject, :read, @object, @environment, [])

    assert answer.meta == %{}
    assert {:ok, ^answer} = Fake.check(@subject, :read, @object, @environment, [])
  end

  test "it allows under verdict: :allow with an allowed reason naming the fake rule" do
    assert {:ok, %Answer{verdict: :allow, reason: :allowed, meta: %{rule: "fake"}}} =
             Fake.check(@subject, :read, @object, @environment, verdict: :allow)
  end

  test "batch answers every object by its reference" do
    other = {:thing, "33333333-3333-3333-3333-333333333333"}
    assert {:ok, answers} = Fake.batch(@subject, :read, [@object, other], @environment, verdict: :allow)
    assert Enum.sort(Map.keys(answers)) == Enum.sort([@object, other])
    assert Enum.all?(answers, fn {_object, %Answer{verdict: verdict}} -> verdict == :allow end)
  end

  test "scope returns a real dynamic that composes into a query" do
    assert {:ok, {rule, %Answer{verdict: :allow}}} = Fake.scope(@subject, :read, :thing, @environment, verdict: :allow)

    query = where(from(row in "things", select: row.id), ^rule)
    assert %Ecto.Query{} = query
    assert {:ok, {denied, %Answer{}}} = Fake.scope(@subject, :read, :thing, @environment, [])
    assert %Ecto.Query{} = where(from(row in "things", select: row.id), ^denied)
  end

  test "explain is unsupported" do
    assert {:error, %Error{reason: :unsupported} = error} = Fake.explain(@subject, :read, @object, @environment, [])

    assert Exception.message(error) =~ "does not support explain"
  end

  test "it declares no ledger requirement, no scope cap, and its options schema" do
    assert Fake.requires_ledger() == false
    assert Fake.scope_cap() == :none
    assert {:ok, [verdict: :deny]} = NimbleOptions.validate([], Fake.options_schema())
  end
end

defmodule Turnstile.Test.FakeTableTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, where: 2]

  alias Turnstile.Answer
  alias Turnstile.Error
  alias Turnstile.Test.Fake

  @user {:user, "acct-a"}
  @other {:user, "acct-b"}
  @folder {:folder, 1}
  @environment %{now: ~U[2026-09-08 00:00:00Z]}

  setup do
    rules = start_supervised!(%{id: Fake, start: {Fake, :start_link, []}})
    {:ok, rules: rules, options: [rules: rules]}
  end

  test "an entry allows one subject one operation on one object and nothing else", %{rules: rules, options: options} do
    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})
    assert {:ok, %Answer{verdict: :allow}} = Fake.check(@user, :read, @folder, @environment, options)
    assert {:ok, %Answer{verdict: :deny}} = Fake.check(@user, :edit, @folder, @environment, options)
    assert {:ok, %Answer{verdict: :deny}} = Fake.check(@other, :read, @folder, @environment, options)
    assert {:ok, %Answer{verdict: :deny}} = Fake.authorize(@user, :read, {:folder, 2}, @environment, options)
    assert Fake.entries(rules) == [{"acct-a", :read, {:folder, 1}}]
    :ok = Fake.revoke(rules, "acct-a", :read, {:folder, 1})
    assert Fake.entries(rules) == []
    assert {:ok, %Answer{verdict: :deny}} = Fake.check(@user, :read, @folder, @environment, options)
  end

  test "any as the subject or the object id is a wildcard", %{rules: rules, options: options} do
    :ok = Fake.allow(rules, :any, :read, {:folder, 1})
    :ok = Fake.allow(rules, "acct-b", :edit, {:folder, :any})
    assert {:ok, %Answer{verdict: :allow}} = Fake.check(@other, :read, @folder, @environment, options)
    assert {:ok, %Answer{verdict: :allow}} = Fake.check(@other, :edit, {:folder, 9}, @environment, options)
    assert {:ok, %Answer{verdict: :deny}} = Fake.check(@user, :edit, @folder, @environment, options)
  end

  test "scope narrows to the ids allowed, everything under a wildcard, nothing without", %{rules: rules, options: options} do
    query = from(row in "folders", select: row.id)

    assert {:ok, {none, %Answer{verdict: :deny}}} = Fake.scope(@user, :read, :folder, @environment, options)

    assert %Ecto.Query{} = where(query, ^none)

    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})

    assert {:ok, {some, %Answer{verdict: :allow}}} = Fake.scope(@user, :read, :folder, @environment, options)

    assert inspect(some) =~ "row.id in"

    :ok = Fake.allow(rules, :any, :read, {:folder, :any})

    assert {:ok, {all, %Answer{verdict: :allow}}} = Fake.scope(@other, :read, :folder, @environment, options)

    assert inspect(all) =~ "true"
  end

  test "a failing table answers every call with an engine error until told otherwise", %{rules: rules, options: options} do
    :ok = Fake.allow(rules, "acct-a", :read, {:folder, 1})
    :ok = Fake.fail(rules, "down")

    assert {:error, %Error{reason: :engine_unreachable, detail: checked}} =
             Fake.check(@user, :read, @folder, @environment, options)

    assert checked == "#{inspect(Fake)} failed during check: down"
    assert_down(Fake.authorize(@user, :read, @folder, @environment, options), :authorize)
    assert_down(Fake.batch(@user, :read, [@folder], @environment, options), :batch)
    assert_down(Fake.scope(@user, :read, :folder, @environment, options), :scope)
    :ok = Fake.fail(rules, nil)
    assert {:ok, %Answer{verdict: :allow}} = Fake.check(@user, :read, @folder, @environment, options)
    :ok = Fake.reset(rules)
    assert Fake.entries(rules) == []
    assert {:ok, %Answer{verdict: :deny}} = Fake.check(@user, :read, @folder, @environment, options)
  end

  # Every callback of a failing table answers the same engine error, naming itself.
  defp assert_down(result, operation) do
    assert {:error, %Error{reason: :engine_unreachable, detail: detail}} = result
    assert detail =~ "during #{operation}"
  end
end
