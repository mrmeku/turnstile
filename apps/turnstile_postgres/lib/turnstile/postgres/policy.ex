defmodule Turnstile.Postgres.Policy do
  @moduledoc """
  One row-level security policy as `pg_policy` holds it: the name, the
  table, the command it applies to, and the `USING` and `WITH CHECK`
  expressions as the database renders them.

  Two names are the adapter's business, and the migration helpers write
  both. `turnstile_scope_<operation>` is a `SELECT` policy that narrows the
  rows of that operation; the helper guards it on
  `current_setting('turnstile.operation', true)`, so two operations on one
  table never widen each other. `turnstile_gate_<operation>` is an `UPDATE`
  policy whose `USING` expression `check` reads before a write and whose
  `WITH CHECK` expression the database applies to the write itself. A
  policy under any other name belongs to whoever wrote it, and `kind/1`
  answers `:other` for it.
  """

  @scope "turnstile_scope_"
  @gate "turnstile_gate_"

  @enforce_keys [:name, :table, :command, :using, :with_check]
  defstruct @enforce_keys

  @typedoc "The command a policy applies to, as `polcmd` spells it."
  @type command :: :all | :select | :insert | :update | :delete

  @type t :: %__MODULE__{
          name: String.t(),
          table: String.t(),
          command: command(),
          using: String.t() | nil,
          with_check: String.t() | nil
        }

  @doc "The name of the scope policy of an operation."
  @spec scope_name(String.t()) :: String.t()
  def scope_name(operation) when is_binary(operation), do: @scope <> operation

  @doc "The name of the gate policy of an operation."
  @spec gate_name(String.t()) :: String.t()
  def gate_name(operation) when is_binary(operation), do: @gate <> operation

  @doc "What the policy is to the adapter: the scope of an operation, its gate, or none of its business."
  @spec kind(t()) :: {:scope, String.t()} | {:gate, String.t()} | :other
  def kind(%__MODULE__{name: name}) do
    cond do
      operation = after_prefix(name, @scope) -> {:scope, operation}
      operation = after_prefix(name, @gate) -> {:gate, operation}
      true -> :other
    end
  end

  @doc "The command letter `polcmd` carries, as an atom."
  @spec command(String.t()) :: command()
  def command("*"), do: :all
  def command("r"), do: :select
  def command("a"), do: :insert
  def command("w"), do: :update
  def command("d"), do: :delete

  @doc "The policy as the text a policy version carries."
  @spec to_text(t()) :: String.t()
  def to_text(%__MODULE__{} = policy) do
    "#{policy.table} #{policy.name} #{policy.command}\n" <>
      "  USING #{policy.using || "-"}\n  WITH CHECK #{policy.with_check || "-"}\n"
  end

  # The rest of the name after a prefix, or `nil` when the name does not
  # carry it or carries nothing after it.
  defp after_prefix(name, prefix) do
    case String.replace_prefix(name, prefix, "") do
      ^name -> nil
      "" -> nil
      rest -> rest
    end
  end
end
