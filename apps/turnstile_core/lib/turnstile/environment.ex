defmodule Turnstile.Environment do
  @moduledoc """
  Under what conditions. `now` comes from the port's clock; `facts` are the
  caller-supplied facts only the caller knows, such as when the session last
  re-authenticated, keyed by name.
  """

  @enforce_keys [:now]
  defstruct [:now, facts: %{}]

  @type t :: %__MODULE__{now: DateTime.t(), facts: %{atom() => term()}}
end
