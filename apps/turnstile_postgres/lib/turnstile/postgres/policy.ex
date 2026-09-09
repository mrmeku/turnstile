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

  alias Turnstile.Postgres.Name

  @scope "turnstile_scope_"
  @gate "turnstile_gate_"
  @identifier ~r/\A[a-z_][a-z0-9_]*\z/
  @commands ~w(all select insert update delete)

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

  @doc """
  The policies a version's text carries, back as structs. An expression the
  database renders runs over several lines, so a line that begins a policy
  is the one holding a table, a name, and a command and nothing else, and
  every other line belongs to the expression above it.
  """
  @spec from_text(String.t()) :: [t()]
  def from_text(text) when is_binary(text) do
    text
    |> String.split("\n")
    |> Enum.reduce([], &read/2)
    |> Enum.reverse()
    |> Enum.map(&close/1)
  end

  @doc """
  The statement that writes the policy. The version carries no role list
  because the helpers write none: a policy of this package applies to every
  role and names the role it admits inside its expression.
  """
  @spec to_sql(t()) :: String.t()
  def to_sql(%__MODULE__{} = policy) do
    "CREATE POLICY #{Name.check!(policy.name, :policy)} ON #{Name.check!(policy.table, :table)} " <>
      "FOR #{sql_command(policy.command)}" <> clause(" USING", policy.using) <> clause(" WITH CHECK", policy.with_check)
  end

  defp sql_command(:all), do: "ALL"
  defp sql_command(:select), do: "SELECT"
  defp sql_command(:insert), do: "INSERT"
  defp sql_command(:update), do: "UPDATE"
  defp sql_command(:delete), do: "DELETE"

  defp clause(_keyword, nil), do: ""
  defp clause(keyword, expression), do: "#{keyword} (#{expression})"

  # One line at a time, newest policy first: a header opens a policy, the two
  # keywords open an expression, and anything else continues the open one.
  defp read(line, read_so_far) do
    case parse(line) do
      {:header, policy} -> [{policy, nil} | read_so_far]
      {:expression, field, first} -> [open(hd(read_so_far), field, first) | tl(read_so_far)]
      :continuation -> [continue(hd(read_so_far), line) | tl(read_so_far)]
      :blank -> read_so_far
    end
  end

  defp parse(line) do
    cond do
      line == "" -> :blank
      header = header(line) -> {:header, header}
      expression = expression(line, "  USING ", :using) -> expression
      expression = expression(line, "  WITH CHECK ", :with_check) -> expression
      true -> :continuation
    end
  end

  defp header(line) do
    with [table, name, command] <- String.split(line, " "),
         true <- Regex.match?(@identifier, table),
         true <- Regex.match?(@identifier, name),
         true <- command in @commands do
      %__MODULE__{
        name: name,
        table: table,
        command: String.to_existing_atom(command),
        using: nil,
        with_check: nil
      }
    else
      _other -> nil
    end
  end

  defp expression(line, keyword, field) do
    case String.split(line, keyword, parts: 2) do
      ["", rest] -> {:expression, field, rest}
      _other -> nil
    end
  end

  defp open({%__MODULE__{} = policy, _field}, field, first), do: {Map.put(policy, field, first), field}

  defp continue({%__MODULE__{} = policy, field}, line) do
    {Map.put(policy, field, Map.fetch!(policy, field) <> "\n" <> line), field}
  end

  defp close({%__MODULE__{} = policy, _field}) do
    %{policy | using: value(policy.using), with_check: value(policy.with_check)}
  end

  defp value("-"), do: nil
  defp value(other), do: other

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
