defmodule Turnstile.PolicyVersion do
  @moduledoc """
  One published version of an adapter's rules. `content` is the text by value
  when it is under the configured cap and `pointer` names where it lives
  otherwise; a decision record carries only the version identifier.
  """

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
end
