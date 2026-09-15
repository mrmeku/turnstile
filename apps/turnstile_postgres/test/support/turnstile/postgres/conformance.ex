defmodule Turnstile.Postgres.Conformance do
  @moduledoc """
  The conformance artifact of row-level security: the migration that
  protects the neutral fixture's tables and writes the policies encoding
  its rule. The test run compiles it; an application never loads it.
  """

  use Boundary,
    top_level?: true,
    deps: [Turnstile.Postgres, Turnstile.Conformance, Turnstile.TestRepos, Ecto],
    exports: [Rules, Versions]
end
