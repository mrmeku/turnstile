defmodule Turnstile.Test.FakeSeed do
  @moduledoc """
  The fake adapter's conformance hooks: `seed/1` rewrites the fake's rule
  table from a world, one entry per grant the world's rule allows, and
  `outage/0` makes every call to the fake fail for the rest of the test.
  Both find the table through the configuration in force, whether the
  adapter bound is the fake or a module of its own that answers from it.
  """

  @behaviour Turnstile.Conformance.Seed

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Conformance, Turnstile.Fixture]

  alias Turnstile.Config
  alias Turnstile.Conformance.Seed
  alias Turnstile.Fixture.World
  alias Turnstile.Test.Fake

  @impl Seed
  def seed(%World{} = world) do
    rules = rules!()
    :ok = Fake.reset(rules)
    Enum.each(World.grants(world), fn {{_kind, id}, operation, ref} -> Fake.allow(rules, id, operation, ref) end)
  end

  @impl Seed
  def outage, do: Fake.fail(rules!(), "the fake's engine is down")

  defp rules! do
    {:ok, %Config{} = config} = Config.resolve()
    {_adapter, options} = Config.adapter(config)
    Keyword.fetch!(options, :rules)
  end
end
