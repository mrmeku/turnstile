defmodule Turnstile.Error.NotAuthorized do
  @moduledoc "The port denied the operation. A value on the request path; the bang variants raise it."

  alias Turnstile.Answer

  @enforce_keys [:subject, :operation, :object, :reason]
  defexception [:subject, :operation, :object, :reason, detail: nil]

  @typedoc "`detail` is what the denying answer put on `meta`, where it put one: the engine's own text."
  @type t :: %__MODULE__{
          subject: Turnstile.subject(),
          operation: atom(),
          object: Turnstile.object() | atom(),
          reason: Answer.reason(),
          detail: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{subject: {kind, id}} = error) do
    "#{kind} #{id} may not #{error.operation} #{inspect(error.object)}: #{error.reason}#{detail(error.detail)}"
  end

  defp detail(nil), do: ""
  defp detail(text), do: " (" <> text <> ")"
end
