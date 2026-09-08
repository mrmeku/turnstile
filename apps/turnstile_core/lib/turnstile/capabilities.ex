defmodule Turnstile.Capabilities do
  @moduledoc """
  What a thin application declares about each rule under its adapter: the
  level, the component that enforces it, and a note. One function clause per
  record plus a fallback, never a map lookup, so the checker sees one atom set
  per rule. Only `:unsupported` skips a scenario.
  """

  @type level :: :native | :limited | :unsupported
  @type component :: :adapter | :seam | :database | :engine | :application
  @type declaration :: {level(), [by: component(), note: String.t()]}

  @doc "The record for a rule, `:c1` to `:c13`, or for a guarantee a scenario names."
  @callback capability(rule :: atom()) :: declaration()

  @doc "The levels."
  @spec levels() :: [level()]
  def levels, do: [:native, :limited, :unsupported]

  @doc "The components."
  @spec components() :: [component()]
  def components, do: [:adapter, :seam, :database, :engine, :application]
end
