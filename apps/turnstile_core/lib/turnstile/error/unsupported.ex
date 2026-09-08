defmodule Turnstile.Error.Unsupported do
  @moduledoc "The adapter, or the configuration, does not support what was asked."

  @enforce_keys [:adapter, :feature, :note]
  defexception @enforce_keys

  @type t :: %__MODULE__{adapter: module(), feature: atom(), note: String.t()}

  @impl Exception
  def message(%__MODULE__{adapter: adapter, feature: feature, note: note}) do
    "#{inspect(adapter)} does not support #{feature}: #{note}"
  end
end
