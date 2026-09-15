defmodule Turnstile.FreezeTest do
  @moduledoc """
  The frozen lists. A change here follows a change to `docs/design.md`,
  `docs/conformance.md`, or `docs/example.md` in its own commit.
  """

  use ExUnit.Case, async: true

  alias Turnstile.Conformance.Scenario
  alias Turnstile.Conformance.Scenarios

  @moduletag :freeze

  @reference Path.expand("../../../../docs/example.md", __DIR__)

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
               scope_cap: 0,
               settle: 0
             )

    assert Enum.sort(Turnstile.Adapter.behaviour_info(:optional_callbacks)) ==
             Enum.sort(explain: 5, around_query: 3, options_schema: 0, settle: 0)
  end

  test "the structs have the frozen fields" do
    assert fields(Turnstile.Answer) == ~w(meta reason verdict version)a
    assert fields(Turnstile.Exemption) == ~w(caller kind on reason)a

    assert fields(Turnstile.Decision) ==
             ~w(adapter at id object operation operation_id policy_version reason subject verdict)a

    assert fields(Turnstile.Config) == ~w(adapter caps clock)a
  end

  test "the subject kinds and the reason lists are the frozen lists" do
    assert Turnstile.Port.subject_kinds() == [:user, :non_person_entity, :privileged]

    assert Turnstile.Answer.reasons() ==
             ~w(allowed deny_by_default rule_denied engine_unreachable missing_fact unknown_operation
                unknown_subject_kind)a

    assert Turnstile.Error.reasons() ==
             ~w(deny_by_default rule_denied engine_unreachable missing_fact unknown_operation unknown_subject_kind
                unsupported invalid unmediated)a
  end

  test "the scenario ids are the frozen list" do
    assert Scenarios.ids() ==
             Enum.map(1..20, &"enf-#{pad(&1)}") ++
               Enum.map(1..8, &"lp-#{pad(&1)}") ++
               Enum.map(1..3, &"sod-#{pad(&1)}") ++
               Enum.map(1..7, &"rev-#{pad(&1)}") ++
               Enum.map(1..8, &"aud-#{pad(&1)}") ++
               ["rvw-01", "rvw-04"] ++
               Enum.map(1..3, &"ia-#{pad(&1)}") ++
               Enum.map(1..3, &"ovr-#{pad(&1)}") ++
               Enum.map(1..3, &"cm-#{pad(&1)}")
  end

  test "the scenario table equals docs/example.md §4" do
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
    |> String.split("\n## 4. The scenarios")
    |> Enum.at(1)
    |> String.split("\n## ")
    |> hd()
    |> String.split("\n")
    |> Enum.filter(&String.starts_with?(&1, "| `"))
    |> Enum.map(&row/1)
  end

  defp row(line) do
    [id, sentence, group, controls, tests] =
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
      tests: tests(tests)
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
