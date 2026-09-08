defmodule Turnstile.PolicyVersion do
  @moduledoc """
  One published version of an adapter's rules. `content` is the text by value
  when it is under the configured cap and `pointer` names where it lives
  otherwise; a decision record carries only the version identifier.
  """

  alias Turnstile.Edge
  alias Turnstile.Error

  @enforce_keys [:adapter, :version, :content_hash, :author, :approval, :at]
  defstruct [:adapter, :version, :content_hash, :author, :approval, :at, content: nil, pointer: nil]

  @typedoc "The version identifier a decision record carries: a commit, a migration number, or a model id."
  @type ref :: String.t()

  @type t :: %__MODULE__{
          adapter: module(),
          version: ref(),
          content_hash: String.t(),
          content: String.t() | nil,
          pointer: String.t() | nil,
          author: String.t(),
          approval: String.t(),
          at: DateTime.t()
        }

  @doc "The version as a map of plain values."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = version) do
    %{
      adapter: Edge.module_out(version.adapter),
      version: version.version,
      content_hash: version.content_hash,
      content: version.content,
      pointer: version.pointer,
      author: version.author,
      approval: version.approval,
      at: Edge.time_out(version.at)
    }
  end

  @doc "A map back to the version."
  @spec from_map(map()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def from_map(map) when is_map(map) do
    with {:ok, fields} <- Edge.convert(map, spec(), :policy_version, [:content, :pointer]) do
      {:ok, struct!(__MODULE__, fields)}
    end
  end

  defp spec do
    [
      adapter: :module,
      version: :string,
      content_hash: :string,
      content: {:string, :nil_ok},
      pointer: {:string, :nil_ok},
      author: :string,
      approval: :string,
      at: :time
    ]
  end
end
