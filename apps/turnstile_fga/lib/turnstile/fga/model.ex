defmodule Turnstile.Fga.Model do
  @moduledoc """
  The model language as text, compiled into the body the server takes.

  A model is an artifact a package ships as text, because text is what a
  reviewer reads and what a policy-version event carries. The server takes
  its models as a tree of usersets instead, and the pinned server (1.19.0)
  ships no command that turns one into the other, so the translation is
  here: `compile/1` answers the map `c:Turnstile.Fga.Client.write_model/3`
  sends, and the text stays the thing under review.

  What the text may say. A `model` line, a `schema 1.1` line, then `type`
  blocks and `condition` blocks. A type block holds a `relations` line and
  one `define` per relation. A definition is a direct list (`[user]`,
  `[user:*]`, `[group#member]`, `[user with while_cleared]`), a relation on
  the same object (`editor`), a relation reached through another
  (`can_read from folder`), or those combined with `or`, `and`, and
  `but not`. Operators of two kinds in one definition need parentheses,
  which is the server's rule as well, and a definition that mixes them
  without parentheses is an error rather than a guess. Comments are not
  read, because `#` names a relation inside a direct list.

  A relation's direct list becomes the entry the server keeps as metadata
  and the rest of the definition becomes its userset, which is why a
  definition of `[user] or lead` says `this` in the tree and names `user` in
  the metadata.
  """

  alias Turnstile.Error

  @schema_version "1.1"

  @parameter_types %{
    "string" => "TYPE_NAME_STRING",
    "int" => "TYPE_NAME_INT",
    "uint" => "TYPE_NAME_UINT",
    "double" => "TYPE_NAME_DOUBLE",
    "bool" => "TYPE_NAME_BOOL",
    "duration" => "TYPE_NAME_DURATION",
    "timestamp" => "TYPE_NAME_TIMESTAMP",
    "ipaddress" => "TYPE_NAME_IPADDRESS",
    "list" => "TYPE_NAME_LIST",
    "map" => "TYPE_NAME_MAP"
  }

  @condition ~r/^condition\s+([A-Za-z_][A-Za-z0-9_]*)\s*\((.*?)\)\s*\{(.*)\}$/s

  @typedoc "The compiled model, as the client sends it."
  @type t :: %{String.t() => term()}

  @doc "The schema version every model this module compiles declares."
  @spec schema_version() :: String.t()
  def schema_version, do: @schema_version

  @doc "The parameter type names a condition may declare, by the word the text uses."
  @spec parameter_types() :: %{String.t() => String.t()}
  def parameter_types, do: @parameter_types

  @doc "The model in a file, compiled."
  @spec read(Path.t()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def read(path) when is_binary(path) do
    case File.read(path) do
      {:ok, text} -> compile(text)
      {:error, reason} -> {:error, invalid("#{path} could not be read: #{:file.format_error(reason)}")}
    end
  end

  @doc "The model language as text, compiled into the body the server takes."
  @spec compile(String.t()) :: {:ok, t()} | {:error, Error.Invalid.t()}
  def compile(text) when is_binary(text) do
    with {:ok, body} <- header(lines(text)),
         {:ok, blocks} <- blocks(body) do
      assembled(blocks)
    end
  end

  @doc "`compile/1`, raising the error."
  @spec compile!(String.t()) :: t()
  def compile!(text) when is_binary(text) do
    case compile(text) do
      {:ok, model} -> model
      {:error, error} -> raise error
    end
  end

  @doc "`read/1`, raising the error."
  @spec read!(Path.t()) :: t()
  def read!(path) when is_binary(path) do
    case read(path) do
      {:ok, model} -> model
      {:error, error} -> raise error
    end
  end

  defp lines(text) do
    text
    |> String.split("\n")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp header(["model", "schema " <> version | body]) do
    if String.trim(version) == @schema_version do
      {:ok, body}
    else
      {:error, invalid("the schema is #{String.trim(version)} and this module compiles #{@schema_version}")}
    end
  end

  defp header(_lines), do: {:error, invalid("a model opens with a model line and a schema line")}

  defp blocks([]), do: {:ok, []}

  defp blocks(["type " <> name | rest]) do
    {body, tail} = Enum.split_while(rest, &inside?/1)

    with {:ok, definitions} <- definitions(body),
         {:ok, blocks} <- blocks(tail) do
      {:ok, [{:type, String.trim(name), definitions} | blocks]}
    end
  end

  defp blocks(["condition " <> _rest = line | rest]) do
    {taken, tail} = closed(line, rest)

    with {:ok, condition} <- condition(Enum.join(taken, "\n")),
         {:ok, blocks} <- blocks(tail) do
      {:ok, [condition | blocks]}
    end
  end

  defp blocks([line | _rest]), do: {:error, invalid("#{line} is outside a type and a condition")}

  defp inside?("type " <> _rest), do: false
  defp inside?("condition " <> _rest), do: false
  defp inside?(_line), do: true

  # A condition block ends at the line its closing brace is on, which is the
  # opening line itself where the whole condition is written on one line.
  defp closed(line, rest) do
    if String.ends_with?(line, "}") do
      {[line], rest}
    else
      {body, tail} = Enum.split_while(rest, &(not String.ends_with?(&1, "}")))
      {[line | body] ++ Enum.take(tail, 1), Enum.drop(tail, 1)}
    end
  end

  defp definitions(lines) do
    step = fn line, {:ok, done} -> defined(line, done) end

    with {:ok, reversed} <- Enum.reduce_while(lines, {:ok, []}, step), do: {:ok, Enum.reverse(reversed)}
  end

  defp defined("relations", done), do: {:cont, {:ok, done}}

  defp defined("define " <> rest, done) do
    case String.split(rest, ":", parts: 2) do
      [relation, body] -> named(String.trim(relation), body, done)
      [_only] -> {:halt, {:error, invalid("define #{rest} names no definition after a colon")}}
    end
  end

  defp defined(line, _done), do: {:halt, {:error, invalid("#{line} is neither relations nor a define")}}

  defp named(relation, body, done) do
    case expression(body) do
      {:ok, node} -> {:cont, {:ok, [{relation, node} | done]}}
      {:error, error} -> {:halt, {:error, error}}
    end
  end

  defp expression(text) do
    with {:ok, tokens} <- tokens(String.trim(text), []),
         {:ok, nodes, operators} <- terms(tokens, [], []) do
      combined(nodes, Enum.uniq(operators))
    end
  end

  defp tokens("", taken), do: {:ok, Enum.reverse(taken)}
  defp tokens(" " <> rest, taken), do: tokens(rest, taken)
  defp tokens("[" <> rest, taken), do: grouped(rest, "]", :direct, taken)
  defp tokens("(" <> rest, taken), do: grouped(rest, ")", :paren, taken)

  defp tokens(text, taken) do
    case String.split(text, " ", parts: 2) do
      [word] -> tokens("", [word | taken])
      [word, rest] -> tokens(rest, [word | taken])
    end
  end

  defp grouped(text, close, kind, taken) do
    case String.split(text, close, parts: 2) do
      [inside, rest] -> tokens(rest, [{kind, inside} | taken])
      [_only] -> {:error, invalid("#{text} is not closed by #{close}")}
    end
  end

  defp terms([], nodes, operators), do: {:ok, Enum.reverse(nodes), Enum.reverse(operators)}
  defp terms(["or" | rest], nodes, operators), do: terms(rest, nodes, [:union | operators])
  defp terms(["and" | rest], nodes, operators), do: terms(rest, nodes, [:intersection | operators])
  defp terms(["but", "not" | rest], nodes, operators), do: terms(rest, nodes, [:difference | operators])

  defp terms([{:direct, inside} | rest], nodes, operators) do
    with {:ok, types} <- types(inside), do: terms(rest, [{:direct, types} | nodes], operators)
  end

  defp terms([{:paren, inside} | rest], nodes, operators) do
    with {:ok, node} <- expression(inside), do: terms(rest, [node | nodes], operators)
  end

  defp terms([relation, "from", through | rest], nodes, operators) when is_binary(relation) and is_binary(through) do
    terms(rest, [{:from, relation, through} | nodes], operators)
  end

  defp terms([relation | rest], nodes, operators) when is_binary(relation) do
    terms(rest, [{:computed, relation} | nodes], operators)
  end

  defp combined([node], []), do: {:ok, node}
  defp combined(nodes, [:union]), do: {:ok, {:union, nodes}}
  defp combined(nodes, [:intersection]), do: {:ok, {:intersection, nodes}}
  defp combined([base, subtract], [:difference]), do: {:ok, {:difference, base, subtract}}

  defp combined(_nodes, operators) do
    {:error, invalid("#{inspect(operators)} in one definition needs parentheses to say which binds first")}
  end

  defp types(inside) do
    entries =
      inside
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    step = fn entry, {:ok, done} -> restriction(entry, done) end

    with {:ok, reversed} <- Enum.reduce_while(entries, {:ok, []}, step), do: {:ok, Enum.reverse(reversed)}
  end

  defp restriction(entry, done) do
    case String.split(entry, " with ", parts: 2) do
      [base] -> {:cont, {:ok, [related(base) | done]}}
      [base, condition] -> {:cont, {:ok, [conditioned(related(base), String.trim(condition)) | done]}}
    end
  end

  defp conditioned(restriction, condition), do: Map.put(restriction, "condition", condition)

  # The three shapes a direct list entry takes: a type, every user of a type,
  # and the holders of one relation on a type.
  defp related(entry) do
    case String.split(entry, ["#", ":"], parts: 2) do
      [type] -> %{"type" => type}
      [type, "*"] -> %{"type" => type, "wildcard" => %{}}
      [type, relation] -> %{"type" => type, "relation" => relation}
    end
  end

  defp condition(text) do
    case Regex.run(@condition, String.trim(text)) do
      [_whole, name, parameters, expression] -> declared(name, parameters, String.trim(expression))
      nil -> {:error, invalid("a condition is a name, its parameters in brackets, and its expression in braces")}
    end
  end

  defp declared(name, parameters, expression) do
    with {:ok, declared} <- parameters(parameters) do
      {:ok, {:condition, name, %{"name" => name, "expression" => expression, "parameters" => declared}}}
    end
  end

  defp parameters(text) do
    entries =
      text
      |> String.split(",")
      |> Enum.map(&String.trim/1)
      |> Enum.reject(&(&1 == ""))

    step = fn entry, {:ok, done} -> parameter(entry, done) end

    with {:ok, declared} <- Enum.reduce_while(entries, {:ok, []}, step), do: {:ok, Map.new(declared)}
  end

  defp parameter(entry, done) do
    case String.split(entry, ":", parts: 2) do
      [name, type] -> typed(String.trim(name), String.trim(type), done)
      [_only] -> {:halt, {:error, invalid("the parameter #{entry} names no type after a colon")}}
    end
  end

  defp typed(name, type, done) do
    case Map.fetch(@parameter_types, type) do
      {:ok, type_name} -> {:cont, {:ok, [{name, %{"type_name" => type_name}} | done]}}
      :error -> {:halt, {:error, invalid("#{type} is not a parameter type this module knows")}}
    end
  end

  defp assembled(blocks) do
    types = for {:type, name, definitions} <- blocks, do: definition(name, definitions)
    conditions = for {:condition, name, declared} <- blocks, do: {name, declared}

    {:ok,
     %{
       "schema_version" => @schema_version,
       "type_definitions" => types,
       "conditions" => Map.new(conditions)
     }}
  end

  defp definition(name, []), do: %{"type" => name}

  defp definition(name, definitions) do
    %{
      "type" => name,
      "relations" => Map.new(definitions, fn {relation, node} -> {relation, userset(node)} end),
      "metadata" => %{"relations" => Map.new(definitions, &metadata/1)}
    }
  end

  defp metadata({relation, node}), do: {relation, %{"directly_related_user_types" => direct(node)}}

  defp direct({:direct, types}), do: types
  defp direct({:union, nodes}), do: Enum.flat_map(nodes, &direct/1)
  defp direct({:intersection, nodes}), do: Enum.flat_map(nodes, &direct/1)
  defp direct({:difference, base, subtract}), do: direct(base) ++ direct(subtract)
  defp direct(_node), do: []

  defp userset({:direct, _types}), do: %{"this" => %{}}
  defp userset({:computed, relation}), do: %{"computedUserset" => %{"relation" => relation}}
  defp userset({:union, nodes}), do: %{"union" => %{"child" => Enum.map(nodes, &userset/1)}}
  defp userset({:intersection, nodes}), do: %{"intersection" => %{"child" => Enum.map(nodes, &userset/1)}}

  defp userset({:from, relation, through}) do
    %{"tupleToUserset" => %{"tupleset" => %{"relation" => through}, "computedUserset" => %{"relation" => relation}}}
  end

  defp userset({:difference, base, subtract}) do
    %{"difference" => %{"base" => userset(base), "subtract" => userset(subtract)}}
  end

  defp invalid(detail), do: %Error.Invalid{what: :model, detail: detail}
end
