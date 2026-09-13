defmodule Turnstile.Conformance.Case do
  @moduledoc """
  The `scenario` macro: a `test` named by the scenario's id and sentence,
  tagged with its rule, its controls, and the capability record the
  application's declaration returns for the rule. An `unsupported` rule
  skips the scenario with the declaration's note as the reason; a scenario
  that needs a ledger carries `needs_ledger: true`, which a mode-none run
  excludes. Every declaration is checked against
  `Turnstile.Conformance.Scenarios` when the module compiles, so a scenario
  cannot drift from the table.

      use Turnstile.Conformance.Case, capabilities: ExamplePostgres.Capabilities

      scenario "enf-01", "A User with an Assignment to a Document's Program reads it",
        control: ["AC-3"], rule: :c1 do
        ...
      end
  """

  alias Turnstile.Conformance.Case
  alias Turnstile.Conformance.Scenario
  alias Turnstile.Conformance.Scenarios

  @doc false
  defmacro __using__(opts) do
    capabilities = Keyword.fetch!(opts, :capabilities)
    async = Keyword.get(opts, :async, true)

    quote do
      use ExUnit.Case, async: unquote(async)

      import Case, only: [scenario: 4]

      @turnstile_capabilities unquote(capabilities)
    end
  end

  @doc "Declare one scenario; see the module documentation."
  defmacro scenario(id, sentence, opts, do: block) do
    quote bind_quoted: [id: id, sentence: sentence, opts: opts], unquote: true do
      tags = Case.__tags__(id, sentence, opts, @turnstile_capabilities)

      for {key, value} <- tags do
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
  @spec __tags__(String.t(), String.t(), keyword(), module()) :: keyword()
  def __tags__(id, sentence, opts, capabilities)
      when is_binary(id) and is_binary(sentence) and is_list(opts) and is_atom(capabilities) do
    scenario = fetch!(id)
    check_sentence!(scenario, sentence)
    rule = check_rule!(scenario, Keyword.fetch!(opts, :rule))
    controls = check_controls!(scenario, Keyword.fetch!(opts, :control))
    {level, by_and_note} = capabilities.capability(rule)

    [scenario: id, rule: rule, controls: controls, capability: {level, by_and_note}] ++
      ledger_tag(scenario) ++ skip_tag(level, by_and_note)
  end

  defp fetch!(id) do
    case Scenarios.fetch(id) do
      {:ok, %Scenario{} = scenario} -> scenario
      :error -> raise ArgumentError, "no scenario #{inspect(id)} in the reference's table"
    end
  end

  defp check_sentence!(%Scenario{id: id, sentence: expected}, sentence) do
    if sentence == expected do
      :ok
    else
      raise ArgumentError, "scenario #{id} reads #{inspect(expected)} in the reference, got: #{inspect(sentence)}"
    end
  end

  defp check_rule!(%Scenario{id: id, tests: tests}, rule) do
    if rule in tests do
      rule
    else
      raise ArgumentError, "scenario #{id} tests #{inspect(tests)}, got rule: #{inspect(rule)}"
    end
  end

  defp check_controls!(%Scenario{id: id, controls: expected}, controls) do
    if controls == expected do
      controls
    else
      raise ArgumentError, "scenario #{id} cites #{inspect(expected)}, got: #{inspect(controls)}"
    end
  end

  defp ledger_tag(%Scenario{needs_ledger: true}), do: [needs_ledger: true]
  defp ledger_tag(%Scenario{needs_ledger: false}), do: []

  defp skip_tag(:unsupported, by_and_note), do: [skip: Keyword.fetch!(by_and_note, :note)]
  defp skip_tag(_level, _by_and_note), do: []
end
