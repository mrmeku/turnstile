defmodule Turnstile.Error.Invalid do
  @moduledoc "A value at an edge did not validate: configuration, a declaration, or a map from outside."

  @enforce_keys [:what, :detail]
  defexception @enforce_keys

  @type t :: %__MODULE__{what: atom(), detail: String.t()}

  @impl Exception
  def message(%__MODULE__{what: what, detail: detail}), do: "invalid #{what}: #{detail}"
end
