defmodule Example.Scenarios.Review do
  @moduledoc "The access-review scenario, rvw-01."

  use Boundary,
    top_level?: true,
    deps: [Example, Example.Fixture, Example.Scenarios.Support, ExUnit]

  import Example.Scenarios.Support
  import ExUnit.Assertions

  alias Example.Fixture

  @spec rvw_01() :: term()
  def rvw_01 do
    world = Fixture.world!()
    open = Fixture.document!(world)
    federal = Fixture.document!(world, controls: [:federal_only])
    foreign = Fixture.document!(world, program: world.foreign_program, office: world.foreign_office)

    settle()
    report = Example.Review.report(subject("eve"), fresh())
    [_head, domestic, foreign_section] = String.split(report, ~r/^agency /m)
    assert_section(domestic, "Domestic", ann: [open, federal], bob: [open], frank: [], ivan: [])
    assert_section(foreign_section, "Foreign", ivan: [foreign], ann: [])
    readers = Example.Review.readers(subject("eve"), world.agency, fresh())
    assert readers[subject("ann")] == [open.id, federal.id]
    assert readers[subject("bob")] == [open.id]
  end

  defp assert_section(section, agency, reads) do
    assert section =~ agency

    for {account, documents} <- reads do
      assert section =~ "#{account} reads [#{Enum.map_join(documents, ", ", & &1.id)}]"
    end
  end
end
