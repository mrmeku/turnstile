defmodule Turnstile.Repo.MatchingTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Turnstile.Adapter.Fake
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Id
  alias Turnstile.Reason
  alias Turnstile.Repo.Matching
  alias Turnstile.Repo.Mediation
  alias Turnstile.Subject
  alias Turnstile.TestRepos.Sandboxed

  test "a query from a table name has no root schema and passes without a mediation" do
    query = from(a in "turnstile_fixture_accounts", select: a.id)
    assert :ok = Matching.judge(query, nil, Sandboxed)
  end

  test "a subquery over a subquery is judged down to its root, and a refusal without a mediation names prepare_query" do
    inner = from(f in Folder, select: f.id)
    query = from(s in subquery(from(x in subquery(inner), select: x.id)), select: s.id)

    error =
      assert_raise(Error.Unmediated, fn ->
        judged = Matching.judge(query, nil, Sandboxed)
        flunk("judged " <> inspect(judged))
      end)

    assert %Error.Unmediated{function: :prepare_query, arity: 3, schema: Folder, caller: __MODULE__} = error

    assert :ok = Matching.judge(query, mediation(:folder), Sandboxed)
  end

  test "a join to a subquery is judged, and a subquery over a table name admits nothing" do
    protected = from(a in "turnstile_fixture_accounts", join: f in subquery(from(f in Folder, select: f.id)), on: true)
    assert_raise Error.Unmediated, fn -> Matching.judge(protected, nil, Sandboxed) end
    assert :ok = Matching.judge(protected, mediation(:folder), Sandboxed)

    schemaless =
      from(a in "turnstile_fixture_accounts",
        join: t in subquery(from(t in "turnstile_fixture_items", select: t.id)),
        on: true
      )

    assert :ok = Matching.judge(schemaless, nil, Sandboxed)
  end

  defp mediation(type) do
    decision = %Decision{
      id: Id.new(),
      subject: %Subject{id: "user-1", kind: :user},
      object: {type, 1},
      operation: :read,
      verdict: :allow,
      reason: %Reason{code: :allowed, message: "allowed by the fake adapter"},
      adapter: Fake,
      policy_version: nil,
      head_position: nil,
      applied_position: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }

    {mediation, _opts} = Mediation.resolve(Sandboxed, {:all, 2}, Folder, turnstile: decision)
    mediation
  end
end
