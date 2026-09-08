defmodule Turnstile.Error.Unmediated do
  @moduledoc """
  A Repo call carried no decision and no exemption, or a decision that does
  not cover the source. Raised, because that is a programming error. It
  names the function, the root source, the decision's object type when one
  was given, the caller where the seam could read it, and a detail where
  the reason is not the plain one.
  """

  @enforce_keys [:function, :arity, :schema]
  defexception [:function, :arity, :schema, object_type: nil, caller: nil, detail: nil]

  @type t :: %__MODULE__{
          function: atom(),
          arity: non_neg_integer(),
          schema: module() | nil,
          object_type: atom() | nil,
          caller: module() | :any | nil,
          detail: String.t() | nil
        }

  @impl Exception
  def message(%__MODULE__{} = error) do
    "Repo.#{error.function}/#{error.arity}#{target(error.schema)} #{reason(error)}#{from(error.caller)}"
  end

  defp target(nil), do: ""
  defp target(schema), do: " on " <> inspect(schema)

  defp reason(%__MODULE__{detail: detail}) when is_binary(detail), do: detail
  defp reason(%__MODULE__{object_type: nil}), do: "carries no decision and no exemption"

  defp reason(%__MODULE__{object_type: type}) do
    "carries a decision for #{inspect(type)}, which does not cover it"
  end

  defp from(caller) when is_atom(caller) and caller not in [nil, :any], do: " (from #{inspect(caller)})"
  defp from(_caller), do: ""
end
