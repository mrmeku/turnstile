defmodule Example.Banner do
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
  covers these laws rather than examples. `Example.Controls` names the
  vocabulary it is written in.
  """

  alias Example.Controls
  alias Example.Core.Markings

  @doc "The marking fields of a row or a map, as a marking with sorted lists."
  @spec marking(map()) :: Controls.marking()
  defdelegate marking(row), to: Markings

  @doc "The banner over a set of rows, each read as the marking it carries."
  @spec of([map()]) :: Controls.marking()
  def of(rows) when is_list(rows), do: Markings.banner(Enum.map(rows, &Markings.marking/1))

  @doc "Whether the banner covers the marking: every subject the banner admits, the marking admits too."
  @spec covers?(map(), map()) :: boolean()
  def covers?(banner, marking) when is_map(banner) and is_map(marking) do
    Markings.covers?(Markings.marking(banner), Markings.marking(marking))
  end
end
