defmodule Example.Scenarios.TableTest do
  @moduledoc """
  The frozen scenario table. A change here follows a change to
  `docs/example.md` §4 in its own commit.
  """

  use ExUnit.Case, async: true

  alias Example.Scenarios.Row
  alias Example.Scenarios.Table

  @moduletag :freeze

  @reference Path.expand("../../../../../docs/example.md", __DIR__)

  test "the scenario ids are the frozen list" do
    assert Table.ids() ==
             Enum.map(1..18, &"enf-#{pad(&1)}") ++
               Enum.map(1..8, &"lp-#{pad(&1)}") ++
               Enum.map(1..3, &"sod-#{pad(&1)}") ++
               Enum.map(1..6, &"rev-#{pad(&1)}") ++
               ["rvw-01"] ++
               Enum.map(1..3, &"ia-#{pad(&1)}") ++
               Enum.map(1..3, &"ovr-#{pad(&1)}")
  end

  test "the scenario table equals docs/example.md §4" do
    assert Table.all() == reference_rows()
  end

  test "the table answers fetch, ids, and the count" do
    assert {:ok, %Row{id: "enf-01", group: :enforcement}} = Table.fetch("enf-01")
    assert :error = Table.fetch("enf-99")
    assert length(Table.ids()) == length(Table.all())
    assert Table.count() == length(Table.all())
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp reference_rows do
    @reference
    |> File.read!()
    |> String.split("\n## 4. The scenarios")
    |> Enum.at(1)
    |> String.split("\n## ")
    |> hd()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| `"))
    |> Enum.map(&row/1)
  end

  defp row(line) do
    [id, sentence, group, controls, tests] = cells(line)

    %Row{
      id: String.trim(id, "`"),
      sentence: sentence,
      group: atomize(group),
      controls: String.split(controls, ", "),
      tests: tests(tests)
    }
  end

  defp cells(line) do
    line
    |> String.split("|")
    |> Enum.drop(1)
    |> Enum.drop(-1)
    |> Enum.map(&String.trim/1)
  end

  # Rules are listed "C1, C6"; the review scenario names the verb.
  defp tests("C" <> _rest = rules) do
    rules
    |> String.split(", ")
    |> Enum.map(&atomize/1)
  end

  defp tests(verb), do: [atomize(verb)]

  defp atomize(text) do
    text
    |> String.replace(["`", ","], "")
    |> String.replace(["-", " "], "_")
    |> String.downcase()
    |> String.to_existing_atom()
  end
end
