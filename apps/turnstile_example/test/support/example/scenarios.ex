defmodule Example.Scenarios do
  @moduledoc """
  Tier 2: every scenario of the reference's table, declared once here and
  defined in a thin application's test module by `use Example.Scenarios,
  capabilities: ThinApp.Capabilities, rules: ThinApp.Rules`. The adapter
  comes from the thin application's boot configuration, not from the test.

  Each scenario's body is a function in a module under this one, named by
  the scenario's id. Scenarios that measure latency, `rev-01` and `rev-06`,
  the reconcile scenario `rvw-04`, the replay scenario `rvw-03`, and the
  change-management scenarios `cm-01`, `cm-02` and `cm-03` run on the
  committed database in a nested module that is not async; every other
  scenario runs in a sandbox transaction. Replay runs there because a
  binding whose rules are the database's own reproduces a decision in a
  database of its own, and the rows it copies over are the committed
  ones. The change-management three publish a rule change, which for
  an adapter whose rules are the database's own is a schema change, and a
  schema change waits for every other connection reading the tables it
  changes; the committed tier runs after the async ones, so it holds the
  only connection there is. The last test counts: the scenarios defined without a skip
  equal the table's rows less the ones the declaration marks `unsupported`
  and, without a ledger, less the ones that need a ledger.

  A thin application supplies through `Example.Scenarios.Rules` the policy
  operations a test cannot write without naming the adapter.
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

  @committed ~w[cm-01 cm-02 cm-03 rev-01 rev-06 rvw-03 rvw-04]

  @doc false
  defmacro __using__(opts) do
    capabilities = Keyword.fetch!(opts, :capabilities)
    rules = Keyword.fetch!(opts, :rules)
    {committed, sandboxed} = Enum.split_with(Scenarios.all(), &(&1.id in @committed))

    quote do
      use Turnstile.Conformance.Case, capabilities: unquote(capabilities), async: true

      setup tags do
        Example.Scenarios.setup(tags, unquote(rules))
      end

      unquote_splicing(Enum.map(sandboxed, &declare(&1, rules)))

      defmodule Committed do
        @moduledoc false
        use Turnstile.Conformance.Case, capabilities: unquote(capabilities), async: false

        setup tags do
          Example.Scenarios.setup(tags, unquote(rules))
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
  scenario; for a committed one, a real connection to the same repo, a
  truncation through the owner repo before the test and another when it
  ends, and the boot policy published into the ledger the truncation
  emptied, so a scenario that reads the record of a rule change starts
  where boot left it.
  """
  @spec setup(map(), module()) :: :ok
  def setup(tags, rules) when is_map(tags) and is_atom(rules) do
    if tags[:committed] do
      :ok = Sandbox.checkout(Example.Repo, sandbox: false)
      :ok = Example.Fixture.truncate!(Example.OwnerRepo)
      :ok = rules.publish_boot()
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
  What a thin application supplies for the scenarios that name the rules
  themselves: a tightened policy under which a program member no longer
  reads, published as a policy version for the calling process, its
  restoration, the boot policy published again for a tier that empties the
  ledger between tests, and a question asked again under a version and a
  state the ledger names.
  """

  @doc "Publish a policy under which `member` no longer holds `read`, returning the version."
  @callback publish_tightened() :: {:ok, Turnstile.PolicyVersion.t()}

  @doc "Restore the boot policy for the calling process."
  @callback restore() :: :ok

  @doc "Publish the boot policy as the version the ledger starts from."
  @callback publish_boot() :: :ok

  @doc """
  Run the function with the state and the policies a replay names in force,
  and answer what it answered. What that costs is the binding's business:
  for rules in code it is the running release matching the version the
  replay names and the relationships of the fold put back; for rules the
  database holds it is a database of its own, carrying the rows and the
  policies of that version.
  """
  @callback replay(Turnstile.Ledger.Replay.t(), (-> result)) :: result when result: var
end
