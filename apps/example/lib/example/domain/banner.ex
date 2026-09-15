defmodule Example.Domain.Banner do
  @moduledoc """
  Rule C4 at the domain's face: a row's marking, the banner over a set of
  rows, and whether a banner covers a marking.

  A document's banner is the marking that admits no subject a portion of it
  denies. Categories and controls are the union of the portions'; the REL TO
  country list is the intersection of the lists of the portions that carry
  that control, so a country one portion withholds is released by no banner.
  `Example.Documents` keeps the banner at write time and refuses a marking
  change that would drop a portion's control.

  The arithmetic reads markings as values and holds nothing, so a property
  covers these laws rather than examples. `Example.Domain.Controls` names
  the vocabulary it is written in.
  """

  alias Example.Domain.Controls

  @fields [:categories, :controls, :releasable_to]

  @doc "The marking fields of a row or a map, with each list sorted and without repeats."
  @spec marking(map()) :: Controls.marking()
  def marking(row) when is_map(row) do
    Map.new(@fields, fn field -> {field, values(row, field)} end)
  end

  @doc """
  The banner over a set of rows, each read as the marking it carries: the
  marking that admits no subject any of them denies, and admits every
  subject all of them admit.

  Categories and controls restrict by carrying a value, so the banner
  carries every one any marking carries. REL TO admits by listing, so the
  banner releases to the countries every marking that carries the control
  releases to, and a marking without the control narrows nothing. Where no
  marking carries `releasable_to` the list is empty and the control is
  absent with it, which releases the banner to everyone rather than to
  no one.
  """
  @spec of([map()]) :: Controls.marking()
  def of(rows) when is_list(rows) do
    markings = Enum.map(rows, &marking/1)

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

  defp values(row, field) do
    row
    |> Map.get(field, [])
    |> List.wrap()
    |> Enum.uniq()
    |> Enum.sort()
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
end
