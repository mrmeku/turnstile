defmodule Example.ReviewTest do
  use Example.FakeCase, async: true

  alias Example.Accounts
  alias Example.Documents
  alias Example.Fixture
  alias Example.Review
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Ledger.Memory
  alias Turnstile.Subject

  @eve %Subject{id: "eve", kind: :user}

  test "readers and permissions come from the port per subject and operation", ctx do
    document = Fixture.document!(ctx.world)
    foreign = Fixture.document!(ctx.world, program: ctx.world.foreign_program, office: ctx.world.foreign_office)
    allow(ctx.rules, "ann", :read, {:document, document.id})
    allow(ctx.rules, "ann", :read, {:document, foreign.id})
    allow(ctx.rules, "dana", :change_marking, {:document, document.id})
    readers = Review.readers(@eve, ctx.world.agency)
    assert readers[Fixture.subject("ann")] == [document.id]
    assert readers[Fixture.subject("bob")] == []
    assert map_size(readers) == length(Fixture.account_ids())
    permissions = Review.permissions(@eve, ctx.world.agency)
    assert permissions[Fixture.subject("dana")][:change_marking] == [document.id]
    assert permissions[Fixture.subject("dana")][:read] == []
    assert permissions[Fixture.subject("ann")][:read] == [document.id]
  end

  test "the report lists readers and permissions per agency, then the privileged accounts", ctx do
    document = Fixture.document!(ctx.world)
    allow(ctx.rules, "ann", :read, {:document, document.id})
    allow(ctx.rules, "dana", :change_marking, {:document, document.id})
    report = Review.report(@eve)

    assert report ==
             Enum.join(
               ["agency Domestic"] ++
                 for(
                   id <- Fixture.account_ids(),
                   do: "  #{id} reads #{if id == "ann", do: "[#{document.id}]", else: "[]"}"
                 ) ++
                 for(
                   op <- Documents.operations(),
                   do: "  ann may #{op} #{if op == :read, do: "[#{document.id}]", else: "[]"}"
                 ) ++
                 for(
                   op <- Documents.operations(),
                   do: "  dana may #{op} #{if op == :change_marking, do: "[#{document.id}]", else: "[]"}"
                 ) ++
                 ["agency Foreign"] ++
                 for(id <- Fixture.account_ids(), do: "  #{id} reads []") ++
                 ["privileged accounts", "  gil (person gil) holds [override]"],
               "\n"
             ) <> "\n"
  end

  test "the rows of today are the port's, one per subject, operation, and object, then the privileged accounts", ctx do
    document = Fixture.document!(ctx.world)
    allow(ctx.rules, "ann", :read, {:document, document.id})
    allow(ctx.rules, "dana", :change_marking, {:document, document.id})
    rows = Review.rows(at: nil)

    assert Enum.map(rows, &{&1.subject, &1.kind, &1.operation, &1.object, &1.note}) == [
             {"ann", :user, :read, "document:#{document.id}", "agency Domestic"},
             {"dana", :user, :change_marking, "document:#{document.id}", "agency Domestic"},
             {"gil", :privileged, :override, "-", "person gil"}
           ]
  end

  test "the rows of a past date are the grants the fold holds there", ctx do
    {:ok, agent} = Memory.start_link()
    ledger = {Memory, agent: agent}
    :ok = Turnstile.Test.with_config(ledger: ledger)
    {:ok, _appended} = Memory.append([agent: agent], [granted("ann", 1, ~U[2026-03-01 09:00:00Z])])
    {:ok, _revoked} = Memory.append([agent: agent], [revoked("ann", 1, ~U[2026-03-10 09:00:00Z])])
    _world = ctx.world

    assert [row] = Review.rows(at: ~D[2026-03-05])
    assert {row.subject, row.kind, row.operation, row.object} == {"ann", :user, :member, "program:1"}
    assert row.note == "as of position 1"
    assert Review.rows(at: ~D[2026-03-15]) == []
  end

  test "a past date with no ledger behind it raises rather than answering for today" do
    assert_raise Error.Unsupported, ~r/point_in_time_review/, fn -> Review.rows(at: ~D[2026-03-05]) end
  end

  test "the reviewer names the record and no account" do
    assert %Subject{id: "turnstile.review", kind: :privileged} = Review.reviewer()
    refute Review.reviewer().id in Fixture.account_ids()
    assert Accounts.privileged() != []
  end

  defp granted(user_id, program_id, at) do
    %FactEvent{
      kind: :relationship,
      subject_ref: {:user, user_id},
      object_ref: {:program, program_id},
      attribute: nil,
      old: nil,
      new: :member,
      position: nil,
      operation_id: "review-test",
      at: at,
      by: Subject.library()
    }
  end

  defp revoked(user_id, program_id, at) do
    %{granted(user_id, program_id, at) | old: :member, new: nil}
  end
end
