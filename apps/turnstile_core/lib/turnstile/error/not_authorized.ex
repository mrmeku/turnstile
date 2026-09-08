defmodule Turnstile.Error.NotAuthorized do
  @moduledoc "The port denied the operation. A value on the request path; the bang variants raise it."

  @enforce_keys [:subject, :operation, :object, :reason]
  defexception @enforce_keys

  @type t :: %__MODULE__{
          subject: Turnstile.Subject.t(),
          operation: atom(),
          object: Turnstile.Object.ref() | atom(),
          reason: Turnstile.Reason.t()
        }

  @impl Exception
  def message(%__MODULE__{subject: subject, operation: operation, object: object, reason: reason}) do
    "#{subject.kind} #{subject.id} may not #{operation} #{inspect(object)}: #{reason.message}"
  end
end
