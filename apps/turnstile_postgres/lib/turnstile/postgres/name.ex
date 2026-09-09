defmodule Turnstile.Postgres.Name do
  @moduledoc """
  A table, column, or policy name on its way into a statement. Names cannot
  be parameters, so every one this package interpolates passes `check!/2`
  first: a lowercase letter or underscore, then lowercase letters, digits,
  and underscores, up to the 63 bytes an identifier can hold. A name that
  does not fit raises rather than reaching the database.
  """

  alias Turnstile.Error

  @plain ~r/\A[a-z_][a-z0-9_]*\z/
  @limit 63

  @doc "The name, or a raise saying which name was refused and what it was for."
  @spec check!(atom() | String.t(), atom()) :: String.t()
  def check!(name, what) when is_atom(name) and not is_nil(name), do: check!(Atom.to_string(name), what)

  def check!(name, what) when is_binary(name) and is_atom(what) do
    if Regex.match?(@plain, name) and byte_size(name) <= @limit do
      name
    else
      raise Error.Invalid, what: what, detail: "#{inspect(name)} is not a plain lowercase identifier"
    end
  end
end
