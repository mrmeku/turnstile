defmodule Example.ReviewTest do
  use Example.FakeCase, async: true

  alias Example.Documents
  alias Example.Fixture
  alias Example.Review

  @eve %Turnstile.Subject{id: "eve", kind: :user}

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
end
