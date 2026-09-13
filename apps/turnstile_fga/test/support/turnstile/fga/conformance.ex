defmodule Turnstile.Fga.Conformance do
  @moduledoc """
  The conformance artifact of this adapter: the tuple mapping for the neutral
  fixture, which is what turns that fixture's fact events into tuples. The
  model those tuples are read under is `priv/conformance/model.fga`, which is
  what the server reads. The test run compiles the module; an application
  never loads it.
  """

  use Boundary, top_level?: true, deps: [Turnstile, Turnstile.Fga], exports: [Mapping]
end
