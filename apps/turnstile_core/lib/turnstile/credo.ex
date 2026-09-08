if Code.ensure_loaded?(Credo.Check) do
  defmodule Turnstile.Credo do
    @moduledoc """
    Core's own Credo checks, for the umbrella's `.credo.exs`. They compile
    only where Credo is a dependency, so a release carries neither.

    - `Turnstile.Credo.NoRawSQL` flags SQL that bypasses the seam.
    - `Turnstile.Credo.UnmediatedRepo` flags an Ecto repo without `use Turnstile.Repo`.
    """

    use Boundary, top_level?: true, deps: []
  end
end
