defmodule Turnstile.Core.MatchingTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [from: 2, subquery: 1]

  alias Turnstile.Core.Matching
  alias Turnstile.Core.Mediation
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Fixture.Folder
  alias Turnstile.Id
  alias Turnstile.Test.Fake

  test "a query from a table name has no root schema and passes without a mediation" do
    query = from(a in "turnstile_fixture_accounts", select: a.id)
    assert :ok = Matching.judge(query, nil, caller())
  end

  test "a subquery over a subquery is judged down to its root, and a refusal without a mediation names prepare_query" do
    inner = from(f in Folder, select: f.id)
    query = from(s in subquery(from(x in subquery(inner), select: x.id)), select: s.id)

    error =
      assert_raise(Error, fn ->
        judged = Matching.judge(query, nil, caller())
        flunk("judged " <> inspect(judged))
      end)

    assert %Error{reason: :unmediated} = error

    assert Exception.message(error) ==
             "Repo.prepare_query/3 on #{inspect(Folder)} carries no decision and no exemption " <>
               "(from #{inspect(__MODULE__)})"

    assert :ok = Matching.judge(query, mediation(:folder), caller())
  end

  test "a join to a subquery is judged, and a subquery over a table name admits nothing" do
    protected = from(a in "turnstile_fixture_accounts", join: f in subquery(from(f in Folder, select: f.id)), on: true)
    assert_raise Error, ~r/carries no decision/, fn -> Matching.judge(protected, nil, caller()) end
    assert :ok = Matching.judge(protected, mediation(:folder), caller())

    schemaless =
      from(a in "turnstile_fixture_accounts",
        join: t in subquery(from(t in "turnstile_fixture_items", select: t.id)),
        on: true
      )

    assert :ok = Matching.judge(schemaless, nil, caller())
  end

  defp mediation(type) do
    decision = %Decision{
      id: Id.new(),
      subject: {:user, "user-1"},
      object: {type, 1},
      operation: :read,
      verdict: :allow,
      reason: :allowed,
      adapter: Fake,
      policy_version: nil,
      operation_id: Id.new(),
      at: DateTime.utc_now()
    }

    Mediation.decided({:all, 2}, Folder, decision)
  end

  # The module a refusal names, which the seam reads from the stack and a
  # test of the rules themselves supplies.
  defp caller, do: fn -> __MODULE__ end
end
