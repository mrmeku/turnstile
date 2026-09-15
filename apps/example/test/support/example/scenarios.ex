defmodule Example.Scenarios do
  @moduledoc """
  Tier 2: every scenario of the reference's table, declared once here and
  defined in a thin application's test module by `use Example.Scenarios,
  rules: ThinApp.Rules`. The adapter comes from the thin application's boot
  configuration, not from the test.

  Each scenario's body is a function in a module under this one, named by
  the scenario's id. Scenarios that measure latency, `rev-01` and `rev-06`,
  the drift scenario `rvw-04`, which writes through the owner-role repo, and
  the change-management scenarios `cm-01`, `cm-02` and `cm-03` run on the
  committed database in a nested module that is not async; every other
  scenario runs in a sandbox transaction. The change-management three
  publish a rule change, which for an adapter whose rules are the database's
  own is a schema change, and a schema change waits for every other
  connection reading the tables it changes; the committed tier runs after the
  async ones, so it holds the only connection there is. The last test
  counts: the scenarios defined are the table's rows, every one of them.

  A thin application supplies through `Example.Scenarios.Rules` the policy
  operations a test cannot write without naming the adapter, and, where its
  engine keeps state of its own, what each test needs in place before it runs.
  """

  use Boundary,
    top_level?: true,
    deps: [
      Example,
      Example.Fixture,
      Example.Scenarios.Audit,
      Example.Scenarios.Enforcement,
      Example.Scenarios.Identity,
      Example.Scenarios.Privilege,
      Example.Scenarios.Revocation,
      Ecto.Adapters.SQL,
      ExUnit,
      Turnstile,
      Turnstile.Conformance,
      Turnstile.Test,
      Turnstile.Dev.Sandbox
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
    Example.Scenarios.Identity
  ]

  @committed ~w[cm-01 cm-02 cm-03 rev-01 rev-06 rvw-04]

  @doc false
  defmacro __using__(opts) do
    rules = Keyword.fetch!(opts, :rules)
    {committed, sandboxed} = Enum.split_with(Scenarios.all(), &(&1.id in @committed))

    quote do
      use Turnstile.Conformance.Case, async: true

      setup tags do
        Example.Scenarios.setup(tags, unquote(rules))
      end

      unquote_splicing(Enum.map(sandboxed, &declare(&1, rules)))

      defmodule Committed do
        @moduledoc false
        use Turnstile.Conformance.Case, async: false

        setup tags do
          Example.Scenarios.setup(tags, unquote(rules))
        end

        unquote_splicing(Enum.map(committed, &declare(&1, rules, [:committed])))
      end

      test "the scenarios defined are the table's rows, every one of them" do
        Example.Scenarios.count!([__MODULE__, __MODULE__.Committed])
      end
    end
  end

  @doc """
  The per-test setup: a sandbox connection for an async scenario; for a
  committed one, a real connection to the same repo and a truncation through
  the owner repo before the test and another when it ends.

  A thin application whose `Example.Scenarios.Rules` defines `setup/1` has it
  called after the connection is there and the tables are empty, since what
  it prepares is where a publish goes.
  """
  @spec setup(map(), module()) :: :ok
  def setup(tags, rules) when is_map(tags) and is_atom(rules) do
    if tags[:committed] do
      :ok = Sandbox.checkout(Example.Repo, sandbox: false)
      :ok = Example.Fixture.truncate!(Example.OwnerRepo)
      :ok = prepared(rules, tags)
      ExUnit.Callbacks.on_exit(fn -> Example.Fixture.truncate!(Example.OwnerRepo) end)
      :ok
    else
      :ok = Turnstile.Dev.Sandbox.setup(Example.Repo, tags)
      prepared(rules, tags)
    end
  end

  @doc "The count test's body: see the module documentation."
  @spec count!([module()]) :: :ok
  def count!(modules) when is_list(modules) do
    declared = declared(modules)
    assert Enum.sort(declared) == Enum.sort(Scenarios.ids())
    assert length(declared) == Scenarios.count()
    :ok
  end

  # An application whose adapter needs nothing per test defines no `setup/1`,
  # so the callback is optional and this is where its absence is answered.
  defp prepared(rules, tags) do
    if Code.ensure_loaded?(rules) and function_exported?(rules, :setup, 1), do: rules.setup(tags), else: :ok
  end

  defp declare(%Scenario{id: id, sentence: sentence, tests: [rule | _rest]}, rules, tags \\ []) do
    {module, function, arity} = body(id)
    arguments = if arity == 1, do: [rules], else: []

    quote do
      unquote_splicing(Enum.map(tags, &quote(do: @tag(unquote(&1)))))

      scenario unquote(id), unquote(sentence), rule: unquote(rule) do
        unquote(module).unquote(function)(unquote_splicing(arguments))
      end
    end
  end

  defp declared(modules) do
    for module <- modules, %ExUnit.Test{tags: %{scenario: id}} <- module.__ex_unit__().tests, do: id
  end

  defp body(id) do
    function = String.replace(id, "-", "_")
    Enum.find_value(@bodies, &defined_in(&1, function)) || raise ArgumentError, "no body for scenario #{id}"
  end

  defp defined_in(module, function) do
    Enum.find_value(module.__info__(:functions), fn {name, arity} ->
      if Atom.to_string(name) == function, do: {module, name, arity}
    end)
  end
end

defmodule Example.Scenarios.Rules do
  @moduledoc """
  What a thin application supplies for the scenarios that name the rules
  themselves: the telemetry event its adapter publishes a policy version on,
  a tightened policy under which a program member no longer reads, published
  as a policy version for the calling process, and its restoration. Where the
  engine keeps state of its own, the per-test setup as well.
  """

  @doc """
  Anything this application's own tier needs per test, before a version is
  published or a fact is written: for an engine that keeps a store of its
  own, the store, the model in it, and the binding and the configuration that
  name them for the calling process. The tags are the test's, so a case on
  the committed database is told from one in a sandbox. Optional: an
  application whose adapter needs nothing per test defines it not at all.
  """
  @callback setup(tags :: map()) :: :ok

  @doc "The telemetry event this application's adapter emits a policy version on."
  @callback version_event() :: [atom()]

  @doc "Publish a policy under which `member` no longer holds `read`, returning the version."
  @callback publish_tightened() :: {:ok, Turnstile.PolicyVersion.t()}

  @doc "Restore the boot policy for the calling process."
  @callback restore() :: :ok

  @optional_callbacks setup: 1
end
