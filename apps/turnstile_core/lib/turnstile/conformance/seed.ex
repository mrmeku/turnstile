defmodule Turnstile.Conformance.Seed do
  @moduledoc """
  How the conformance template makes an adapter agree with a world of the
  neutral fixture, for an adapter whose state is not the fixture's tables.
  `seed/1` runs after every write of a world through the seam; an adapter
  that reads the tables needs no seed module. `outage/0` makes the
  adapter's engine unreachable for the rest of the test, and the
  fail-closed case is defined only for a template given `outage:`.
  """

  alias Turnstile.Fixture.World

  @doc "Make the adapter's state agree with the world, from scratch."
  @callback seed(World.t()) :: :ok

  @doc "Make the engine unreachable for the rest of the test."
  @callback outage() :: :ok

  @optional_callbacks outage: 0
end
