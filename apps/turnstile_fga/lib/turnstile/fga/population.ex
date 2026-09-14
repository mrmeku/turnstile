defmodule Turnstile.Fga.Population do
  @moduledoc """
  What `Turnstile.Fga.TupleMappingCase` and `Turnstile.Fga.OutboxCase` write
  and take away: the one thing a template cannot know, since which rows a
  mapping states tuples about is the application's.

  Both writes go through the seam, a row at a time, because what the
  templates hold is the change each row publishes and what a drain then
  does with it. A population large enough to page a read is worth writing
  here, since a single page proves less than the template claims.
  """

  @doc "Write rows the mapping states tuples about, through the seam, from empty tables."
  @callback write(repo :: module()) :: :ok

  @doc "Take every row `write/1` wrote away again, through the seam."
  @callback clear(repo :: module()) :: :ok

  @doc "An object of this type that no row names."
  @callback absent(type :: String.t()) :: String.t()

  @doc """
  Change one row the mapping states a tuple about, leaving the object that
  tuple belongs to in the tables. What a drain can put right is what the
  tables still name, so a disturbance that takes the object away as well is
  a rebuild's to answer rather than a drain's.
  """
  @callback disturb(repo :: module()) :: :ok
end
