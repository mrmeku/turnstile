defmodule Example.Scenarios.Case do
  @moduledoc """
  The `scenario` macro: a `test` named by the scenario's id and sentence,
  and tagged with them. The tags are the id, the rule the declaration says
  it tests, and the controls the document cites for it, which the table
  carries rather than the declaration, so a control id is written in one
  place. Every declaration is checked against `Example.Scenarios.Table`
  when the module compiles, so a scenario cannot drift from the table.

  What a binding enforces each rule with is prose in that binding's README,
  a table a person writes and keeps. Nothing here reads it, and a scenario
  runs under every binding.

      use Example.Scenarios.Case

      scenario "enf-01", "A User with an Assignment to a Document's Program reads it", rule: :c1 do
        ...
      end
  """

  alias Example.Scenarios.Case
  alias Example.Scenarios.Row
  alias Example.Scenarios.Table

  @doc false
  defmacro __using__(opts) do
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      import Case, only: [scenario: 4]
    end
  end

  @doc "Declare one scenario; see the module documentation."
  defmacro scenario(id, sentence, opts, do: block) do
    quote bind_quoted: [id: id, sentence: sentence, opts: opts], unquote: true do
      for {key, value} <- Case.__tags__(id, sentence, opts) do
        @tag [{key, value}]
      end

      test Case.__name__(id, sentence) do
        unquote(block)
      end
    end
  end

  @doc false
  @spec __name__(String.t(), String.t()) :: String.t()
  def __name__(id, sentence) when is_binary(id) and is_binary(sentence), do: id <> " " <> sentence

  @doc false
  @spec __tags__(String.t(), String.t(), keyword()) :: keyword()
  def __tags__(id, sentence, opts) when is_binary(id) and is_binary(sentence) and is_list(opts) do
    scenario = fetch!(id)
    check_sentence!(scenario, sentence)
    rule = check_rule!(scenario, Keyword.fetch!(opts, :rule))

    [scenario: id, rule: rule, controls: scenario.controls]
  end

  defp fetch!(id) do
    case Table.fetch(id) do
      {:ok, %Row{} = scenario} -> scenario
      :error -> raise ArgumentError, "no scenario #{inspect(id)} in the table"
    end
  end

  defp check_sentence!(%Row{id: id, sentence: expected}, sentence) do
    if sentence == expected do
      :ok
    else
      raise ArgumentError, "scenario #{id} reads #{inspect(expected)} in the table, got: #{inspect(sentence)}"
    end
  end

  defp check_rule!(%Row{id: id, tests: tests}, rule) do
    if rule in tests do
      rule
    else
      raise ArgumentError, "scenario #{id} tests #{inspect(tests)}, got rule: #{inspect(rule)}"
    end
  end
end
