defmodule Turnstile.Exemption do
  @moduledoc """
  A named, logged opt-out from mediation, per call. `:declared` carries the
  caller's reason; `:library` is the seam's own writes and is accepted only
  from a `Turnstile.*` module.
  """

  @enforce_keys [:on, :caller, :reason, :kind]
  defstruct @enforce_keys

  @type kind :: :declared | :library

  @typedoc "`on` is the root source: a schema module, a table name, or `nil` for raw SQL."
  @type t :: %__MODULE__{
          on: module() | String.t() | nil,
          caller: module() | :any,
          reason: String.t(),
          kind: kind()
        }

  @doc "The two kinds."
  @spec kinds() :: [kind()]
  def kinds, do: [:declared, :library]
end
