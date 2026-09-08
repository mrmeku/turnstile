defmodule Turnstile.Error.Unmediated do
  @moduledoc "A Repo call carried no decision and no exemption. Raised, because that is a programming error."

  @enforce_keys [:function, :arity, :schema]
  defexception @enforce_keys

  @type t :: %__MODULE__{function: atom(), arity: non_neg_integer(), schema: module() | nil}

  @impl Exception
  def message(%__MODULE__{function: function, arity: arity, schema: schema}) do
    target = if schema, do: " on " <> inspect(schema), else: ""
    "Repo.#{function}/#{arity}#{target} carries no decision and no exemption"
  end
end
