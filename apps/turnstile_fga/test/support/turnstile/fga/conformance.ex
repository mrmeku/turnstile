defmodule Turnstile.Fga.Conformance do
  @moduledoc """
  The conformance artifact of this adapter: the tuple mapping for the neutral
  fixture, which is what states that fixture's tables as tuples, a population
  of those tables for the case templates to write and take away, and what
  those templates run under. The model the tuples are read beneath is
  `priv/conformance/model.fga`, which is what the server reads. The test run
  compiles these; an application never loads them.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Ecto,
      ExUnit,
      Turnstile,
      Turnstile.Fga,
      Turnstile.Fga.Client.Fake,
      Turnstile.Fixture,
      Turnstile.Test,
      Turnstile.Dev.Sandbox
    ],
    exports: [Mapping, Population, Setup]
end
