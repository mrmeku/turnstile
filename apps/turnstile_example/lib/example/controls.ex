defmodule Example.Controls do
  @moduledoc """
  The dissemination controls and the marking values, as the domain's own
  vocabulary: the four control kinds, the fields a marking carries, and the
  banner a set of markings has, which is the marking that admits no subject
  any of them denies.
  """

  @controls [:federal_only, :no_foreign, :named_list, :releasable_to]
  @fields [:categories, :controls, :releasable_to]

  @typedoc "One dissemination control: a test on the subject below the default of lawful purpose."
  @type control :: :federal_only | :no_foreign | :named_list | :releasable_to

  @typedoc "The marking fields a portion carries and a document's banner combines."
  @type marking :: %{categories: [String.t()], controls: [control()], releasable_to: [String.t()]}

  @doc "Every control kind, in the Registry's order."
  @spec all() :: [control()]
  def all, do: @controls

  @doc "The marking fields."
  @spec fields() :: [atom()]
  def fields, do: @fields

  @doc "The marking fields of a row or a map, as a marking with sorted lists."
  @spec marking(map()) :: marking()
  def marking(row) when is_map(row) do
    Map.new(@fields, fn field -> {field, values(row, field)} end)
  end

  @doc """
  The banner over a set of markings: the marking that admits no subject any
  of them denies, and admits every subject all of them admit.

  Categories and controls restrict by carrying a value, so the banner
  carries every one any marking carries. REL TO admits by listing, so the
  banner releases to the countries every marking that carries the control
  releases to, and a marking without the control narrows nothing. Where no
  marking carries `releasable_to` the list is empty and the control is
  absent with it, which releases the banner to everyone rather than to
  no one.
  """
  @spec banner([map()]) :: marking()
  def banner(markings) when is_list(markings) do
    markings = Enum.map(markings, &marking/1)

    %{
      categories: union(markings, :categories),
      controls: union(markings, :controls),
      releasable_to: releases(markings)
    }
  end

  @doc """
  Whether the banner covers the marking: every subject the banner admits,
  the marking admits too.

  The banner carries every category and every control of the marking, and,
  where the marking carries `releasable_to`, releases to no country outside
  the marking's list.
  """
  @spec covers?(map(), map()) :: boolean()
  def covers?(banner, marking) when is_map(banner) and is_map(marking) do
    banner = marking(banner)
    marking = marking(marking)

    Enum.all?([:categories, :controls], fn field -> marking[field] -- banner[field] == [] end) and
      releases_within?(banner, marking)
  end

  defp union(markings, field) do
    markings
    |> Enum.flat_map(& &1[field])
    |> Enum.uniq()
    |> Enum.sort()
  end

  defp releases(markings) do
    case Enum.filter(markings, &(:releasable_to in &1.controls)) do
      [] ->
        []

      [first | rest] ->
        rest
        |> Enum.reduce(MapSet.new(first.releasable_to), &MapSet.intersection(&2, MapSet.new(&1.releasable_to)))
        |> Enum.sort()
    end
  end

  defp releases_within?(banner, marking) do
    :releasable_to not in marking.controls or banner.releasable_to -- marking.releasable_to == []
  end

  defp values(row, field) do
    row
    |> Map.get(field, [])
    |> List.wrap()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
