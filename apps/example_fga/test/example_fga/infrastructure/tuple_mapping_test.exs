defmodule ExampleFga.Infrastructure.TupleMappingTest do
  use Turnstile.Fga.TupleMappingCase,
    async: true,
    mapping: ExampleFga.Infrastructure.TupleMapping,
    repo: Example.Infrastructure.Repo,
    population: ExampleFga.Population,
    sandbox: Turnstile.Dev.Sandbox

  import Ecto.Query, only: [from: 2]

  alias Example.Domain.Document
  alias Example.Domain.Program
  alias Example.Infrastructure.Repo
  alias ExampleFga.Infrastructure.TupleMapping
  alias Turnstile.Fga.TupleKey

  @exemption {:exempt, "tuple mapping test: the rows a tuple is read from"}

  test "a control the banner carries is the wildcard on the relation named for it, under the document's decontrol" do
    tuples = TupleMapping.tuples(Repo, "document:#{document("controlled")}")
    flags = for %TupleKey{user: "user:*"} = tuple <- tuples, do: {tuple.relation, tuple.condition.name}

    assert Enum.sort(flags) == [
             {"list_applies", "before_decontrol"},
             {"noforn_applies", "before_decontrol"},
             {"relto_applies", "before_decontrol"}
           ]
  end

  test "a document with no decontrol date states its tuples plain" do
    tuples = TupleMapping.tuples(Repo, "document:#{document("plain")}")

    assert Enum.all?(tuples, &(&1.condition == nil))
  end

  test "a portion carries the decontrol date of the document it belongs to" do
    id = document("controlled")
    carried = for %TupleKey{relation: "category"} = tuple <- TupleMapping.tuples(Repo, "document:#{id}"), do: tuple
    portions = for object <- TupleMapping.objects(Repo, "portion"), do: TupleMapping.tuples(Repo, object)
    conditions = for tuple <- List.flatten(portions), tuple.relation == "category", do: tuple.condition

    assert conditions != []
    assert Enum.all?(conditions, &(&1 == hd(carried).condition))
  end

  test "a closed program requires no tuple, and every assignment to it stops holding one" do
    assert TupleMapping.tuples(Repo, "program:#{closed()}") == []
  end

  test "an account's nationality and its employment are membership of objects of their own" do
    tuples = TupleMapping.tuples(Repo, "country:FR") ++ TupleMapping.tuples(Repo, "employment:contractor")

    assert Enum.sort(Enum.map(tuples, & &1.user)) == ["user:bob", "user:carl", "user:ivan"]
    assert Enum.all?(tuples, &(&1.relation == "member"))
  end

  defp document(title) do
    query = from(document in Document, where: document.title == ^title, select: document.id)

    Repo.one!(query, turnstile: @exemption)
  end

  defp closed do
    query = from(program in Program, where: not is_nil(program.closed_at), select: program.id)

    Repo.one!(query, turnstile: @exemption)
  end
end
