defmodule Turnstile.Error.Engine do
  @moduledoc "The adapter's engine failed or could not be reached. The port fails closed on it."

  @enforce_keys [:adapter, :operation, :detail]
  defexception @enforce_keys

  @type t :: %__MODULE__{adapter: module(), operation: atom(), detail: String.t()}

  @impl Exception
  def message(%__MODULE__{adapter: adapter, operation: operation, detail: detail}) do
    "#{inspect(adapter)} failed during #{operation}: #{detail}"
  end
end
