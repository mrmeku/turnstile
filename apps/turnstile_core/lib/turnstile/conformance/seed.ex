defmodule Turnstile.Conformance.Seed do
  @moduledoc """
  How the conformance template makes an adapter agree with a population,
  for an adapter whose state is not the world's own tables. `seed/1` runs
  after every write of a population through the seam; an adapter that reads
  the tables needs no seed module. `outage/0` makes the adapter's engine
  unreachable for the rest of the test, and the fail-closed case is defined
  only for a template given `outage:`.
  """

  alias Turnstile.Conformance.World

  @doc "Make the adapter's state agree with the population, from scratch."
  @callback seed(World.t()) :: :ok

  @doc "Make the engine unreachable for the rest of the test."
  @callback outage() :: :ok

  @optional_callbacks outage: 0
end
