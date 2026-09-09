defmodule Example.Controls do
  @moduledoc """
  The dissemination controls and the marking values, as the domain's own
  vocabulary: the four control kinds, the fields a marking carries, and the
  union of markings that is a document's banner.
  """

  @controls [:federal_only, :no_foreign, :named_list, :releasable_to]
  @fields [:categories, :controls, :releasable_to]

  @typedoc "One dissemination control: a test on the subject below the default of lawful purpose."
  @type control :: :federal_only | :no_foreign | :named_list | :releasable_to

  @typedoc "The marking fields a portion carries and a document's banner unions."
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

  @doc "The union of markings: the banner over a set of portions."
  @spec union([map()]) :: marking()
  def union(markings) when is_list(markings) do
    Enum.reduce(markings, marking(%{}), fn row, acc ->
      Map.new(@fields, fn field -> {field, Enum.sort(Enum.uniq(acc[field] ++ marking(row)[field]))} end)
    end)
  end

  @doc "Whether the banner covers the marking: every value of every field is in the banner."
  @spec covers?(map(), map()) :: boolean()
  def covers?(banner, marking) when is_map(banner) and is_map(marking) do
    banner = marking(banner)
    Enum.all?(marking(marking), fn {field, values} -> values -- banner[field] == [] end)
  end

  defp values(row, field) do
    row
    |> Map.get(field, [])
    |> List.wrap()
    |> Enum.uniq()
    |> Enum.sort()
  end
end
