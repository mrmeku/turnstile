defmodule Turnstile.Error.NotAuthorized do
  @moduledoc "The port denied the operation. A value on the request path; the bang variants raise it."

  @enforce_keys [:subject, :operation, :object, :reason]
  defexception @enforce_keys

  @type t :: %__MODULE__{
          subject: Turnstile.subject(),
          operation: atom(),
          object: Turnstile.object() | atom(),
          reason: Turnstile.Reason.t()
        }

  @impl Exception
  def message(%__MODULE__{subject: {kind, id}, operation: operation, object: object, reason: reason}) do
    "#{kind} #{id} may not #{operation} #{inspect(object)}: #{reason.message}"
  end
end
