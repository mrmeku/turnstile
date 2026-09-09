defmodule Example.Scenarios do
  @moduledoc """
  Tier 2: every scenario of the reference's table, declared once here and
  defined in a thin application's test module by `use Example.Scenarios,
  capabilities: ThinApp.Capabilities, rules: ThinApp.Rules`. The adapter
  comes from the thin application's boot configuration, not from the test.

  Each scenario's body is a function in a module under this one, named by
  the scenario's id. Scenarios that measure latency, `rev-01` and `rev-06`,
  and the reconcile scenario `rvw-04` run on the committed database in a
  nested module that is not async; every other scenario runs in a sandbox
  transaction. The last test counts: the scenarios defined without a skip
  equal the table's rows less the ones the declaration marks `unsupported`
  and, without a ledger, less the ones that need a ledger.

  A thin application supplies the two policy operations a test cannot write
  without naming the adapter through `Example.Scenarios.Rules`.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios.Audit,
      Example.Scenarios.Enforcement,
      Example.Scenarios.Identity,
      Example.Scenarios.Ledger,
      Example.Scenarios.Privilege,
      Example.Scenarios.Revocation,
      Ecto.Adapters.SQL,
      ExUnit,
      Turnstile,
      Turnstile.Conformance,
      Turnstile.Test,
      Turnstile.Test.Sandbox
    ],
    exports: [Rules]

  import ExUnit.Assertions

  alias Ecto.Adapters.SQL.Sandbox
  alias Turnstile.Conformance.Scenario
  alias Turnstile.Conformance.Scenarios

  @bodies [
    Example.Scenarios.Enforcement,
    Example.Scenarios.Privilege,
    Example.Scenarios.Revocation,
    Example.Scenarios.Audit,
    Example.Scenarios.Identity,
    Example.Scenarios.Ledger
  ]

  @committed ~w[rev-01 rev-06 rvw-04]

  @doc false
  defmacro __using__(opts) do
    capabilities = Keyword.fetch!(opts, :capabilities)
    rules = Keyword.fetch!(opts, :rules)
    {committed, sandboxed} = Enum.split_with(Scenarios.all(), &(&1.id in @committed))

    quote do
      use Turnstile.Conformance.Case, capabilities: unquote(capabilities), async: true

      setup tags do
        Example.Scenarios.setup(tags)
      end

      unquote_splicing(Enum.map(sandboxed, &declare(&1, rules)))

      defmodule Committed do
        @moduledoc false
        use Turnstile.Conformance.Case, capabilities: unquote(capabilities), async: false

        setup tags do
          Example.Scenarios.setup(tags)
        end

        unquote_splicing(Enum.map(committed, &declare(&1, rules, [:committed])))
      end

      test "the count of scenarios defined without a skip is the table's expected count" do
        Example.Scenarios.count!([__MODULE__, __MODULE__.Committed], unquote(capabilities))
      end
    end
  end

  @doc """
  The per-test setup: a sandbox connection and a counter row for an async
  scenario; for a committed one, a real connection to the same repo and a
  truncation through the owner repo when the test ends.
  """
  @spec setup(map()) :: :ok
  def setup(tags) when is_map(tags) do
    if tags[:committed] do
      :ok = Sandbox.checkout(Example.Repo, sandbox: false)
      ExUnit.Callbacks.on_exit(fn -> Example.Fixture.truncate!(Example.OwnerRepo) end)
      :ok
    else
      Turnstile.Test.Sandbox.setup(Example.Repo, tags)
    end
  end

  @doc "The count test's body: see the module documentation."
  @spec count!([module()], module()) :: :ok
  def count!(modules, capabilities) when is_list(modules) and is_atom(capabilities) do
    declared = declared(modules)
    assert Enum.sort(Enum.map(declared, &elem(&1, 0))) == Enum.sort(Scenarios.ids())
    Enum.each(declared, fn {id, tags} -> assert_tags(id, tags, capabilities) end)
    assert_count(declared, capabilities, ledger_mode())
  end

  defp declare(%Scenario{id: id, sentence: sentence, controls: controls, tests: [rule | _rest]}, rules, tags \\ []) do
    {module, function, arity} = body(id)
    arguments = if arity == 1, do: [rules], else: []

    quote do
      unquote_splicing(Enum.map(tags, &quote(do: @tag(unquote(&1)))))

      scenario unquote(id), unquote(sentence), control: unquote(controls), rule: unquote(rule) do
        unquote(module).unquote(function)(unquote_splicing(arguments))
      end
    end
  end

  defp declared(modules) do
    for module <- modules, %ExUnit.Test{tags: %{scenario: id} = tags} <- module.__ex_unit__().tests, do: {id, tags}
  end

  defp assert_count(declared, capabilities, mode) do
    defined = Enum.count(declared, fn {_id, tags} -> runs?(tags, mode) end)
    assert defined > 0
    assert defined == Scenarios.expected_count(capabilities, mode)
    :ok
  end

  defp assert_tags(id, tags, capabilities) do
    {:ok, scenario} = Scenarios.fetch(id)
    unsupported? = Scenarios.unsupported?(capabilities, scenario)
    assert Map.has_key?(tags, :skip) == unsupported?, "#{id} is skipped without an unsupported declaration"
    assert Map.get(tags, :needs_ledger, false) == scenario.needs_ledger
  end

  defp runs?(tags, mode), do: not Map.has_key?(tags, :skip) and (mode == :ecto or not Map.get(tags, :needs_ledger, false))

  defp body(id) do
    function = String.replace(id, "-", "_")
    Enum.find_value(@bodies, &defined_in(&1, function)) || raise ArgumentError, "no body for scenario #{id}"
  end

  defp defined_in(module, function) do
    Enum.find_value(module.__info__(:functions), fn {name, arity} ->
      if Atom.to_string(name) == function, do: {module, name, arity}
    end)
  end

  defp ledger_mode do
    case Turnstile.Config.resolve() do
      {:ok, %Turnstile.Config{ledger: :none}} -> :none
      {:ok, %Turnstile.Config{}} -> :ecto
    end
  end
end

defmodule Example.Scenarios.Rules do
  @moduledoc """
  What a thin application supplies for the scenarios that publish a rule
  change: a tightened policy under which a program member no longer reads,
  published as a policy version for the calling process, and its restoration.
  """

  @doc "Publish a policy under which `member` no longer holds `read`, returning the version."
  @callback publish_tightened() :: {:ok, Turnstile.PolicyVersion.t()}

  @doc "Restore the boot policy for the calling process."
  @callback restore() :: :ok
end
