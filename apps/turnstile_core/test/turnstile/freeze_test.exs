defmodule Turnstile.FreezeTest do
  @moduledoc """
  The frozen lists of S1. A change here follows a change to `PLAN.md` or
  `docs/reference.md` in its own commit.
  """

  use ExUnit.Case, async: true

  alias Ecto.Adapters.SQL
  alias Turnstile.Conformance.Scenario
  alias Turnstile.Conformance.Scenarios
  alias Turnstile.TestRepos.Owner

  @moduletag :freeze

  @reference Path.expand("../../../../docs/reference.md", __DIR__)

  test "Turnstile.Adapter has the frozen callbacks" do
    assert Enum.sort(Turnstile.Adapter.behaviour_info(:callbacks)) ==
             Enum.sort(
               authorize: 5,
               check: 5,
               batch: 5,
               scope: 5,
               explain: 5,
               around_query: 3,
               options_schema: 0,
               requires_ledger: 0,
               scope_cap: 0,
               projection: 0
             )

    assert Enum.sort(Turnstile.Adapter.behaviour_info(:optional_callbacks)) ==
             Enum.sort(explain: 5, around_query: 3, options_schema: 0, projection: 0)
  end

  test "Turnstile.Ledger has the frozen callbacks" do
    assert Enum.sort(Turnstile.Ledger.behaviour_info(:callbacks)) ==
             Enum.sort(append: 2, read: 3, head: 1, options_schema: 0)
  end

  test "Turnstile.Projection has the frozen callbacks" do
    assert Enum.sort(Turnstile.Projection.behaviour_info(:callbacks)) ==
             Enum.sort(checkpoint: 1, drain_once: 1, rebuild: 1, reconcile: 1)
  end

  test "the structs have the frozen fields" do
    assert fields(Turnstile.FactEvent) ==
             ~w(at attribute by kind new object_ref old operation_id position subject_ref)a

    assert fields(Turnstile.Exemption) == ~w(caller kind on reason)a
    assert Turnstile.Exemption.kinds() == [:declared, :library]

    assert fields(Turnstile.Decision) ==
             ~w(adapter applied_position at head_position id object operation operation_id policy_version reason subject verdict)a

    assert fields(Turnstile.Config) == ~w(adapter caps clock ledger ledger_counter)a
  end

  test "turnstile_ledger_counter has the frozen columns" do
    %{rows: rows} =
      SQL.query!(
        Owner,
        "SELECT column_name::text, data_type::text FROM information_schema.columns " <>
          "WHERE table_name = 'turnstile_ledger_counter' ORDER BY ordinal_position"
      )

    assert rows == [["name", "text"], ["position", "bigint"]]
  end

  test "the scenario ids are the frozen list" do
    assert Scenarios.ids() ==
             Enum.map(1..19, &"enf-#{pad(&1)}") ++
               Enum.map(1..8, &"lp-#{pad(&1)}") ++
               Enum.map(1..3, &"sod-#{pad(&1)}") ++
               Enum.map(1..7, &"rev-#{pad(&1)}") ++
               Enum.map(1..8, &"aud-#{pad(&1)}") ++
               Enum.map(1..4, &"rvw-#{pad(&1)}") ++
               Enum.map(1..3, &"ia-#{pad(&1)}") ++
               Enum.map(1..3, &"ovr-#{pad(&1)}") ++
               Enum.map(1..3, &"cm-#{pad(&1)}")
  end

  test "the scenario table equals the reference's §3a" do
    assert Scenarios.all() == reference_rows()
  end

  defp fields(module) do
    module.__struct__()
    |> Map.keys()
    |> List.delete(:__struct__)
    |> Enum.sort()
  end

  defp pad(n), do: String.pad_leading(Integer.to_string(n), 2, "0")

  defp reference_rows do
    @reference
    |> File.read!()
    |> String.split("\n## §3a ")
    |> Enum.at(1)
    |> String.split("\n## ")
    |> hd()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| `"))
    |> Enum.map(&row/1)
  end

  defp row(line) do
    [id, sentence, group, controls, tests, needs] =
      line
      |> String.split("|")
      |> Enum.drop(1)
      |> Enum.drop(-1)
      |> Enum.map(&String.trim/1)

    %Scenario{
      id: String.trim(id, "`"),
      sentence: sentence,
      group: atomize(group),
      controls: String.split(controls, ", "),
      tests: tests(tests),
      needs_ledger: needs == "ledger"
    }
  end

  # Rules are listed "C1, C6"; a guarantee is one phrase and may carry a comma.
  defp tests("C" <> _rest = rules) do
    rules
    |> String.split(", ")
    |> Enum.map(&atomize/1)
  end

  defp tests(guarantee), do: [atomize(guarantee)]

  defp atomize(text) do
    text
    |> String.replace(["`", ","], "")
    |> String.replace(["-", " "], "_")
    |> String.downcase()
    |> String.to_existing_atom()
  end
end
