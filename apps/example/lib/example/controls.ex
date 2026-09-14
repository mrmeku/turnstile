defmodule Example.Controls do
  @moduledoc """
  The dissemination controls and the marking values, as the domain's own
  vocabulary: the four control kinds and the fields a marking carries.

  Every schema that holds a marking reads its control values from here, and
  `Example.Banner` is where a set of markings adds up to a banner (C4).
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
end
