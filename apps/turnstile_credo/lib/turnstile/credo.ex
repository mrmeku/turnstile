if Code.ensure_loaded?(Credo.Check) do
  defmodule Turnstile.Credo do
    @moduledoc """
    Two checks an adopter adds to `.credo.exs`, in a package of their own
    because they carry Credo and the contract does not.

    - `Turnstile.Credo.NoRawSQL` flags SQL that reaches the database around
      the seam.
    - `Turnstile.Credo.UnmediatedRepo` flags an Ecto repo without
      `use Turnstile.Repo`.

    Both read source text, so this package depends on no other package here.
    Credo is a development and test dependency, as it is for every package
    of this umbrella, and the checks compile where it is present.
    """

    use Boundary, top_level?: true, deps: [Credo]
  end
end
