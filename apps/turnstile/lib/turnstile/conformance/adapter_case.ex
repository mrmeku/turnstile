defmodule Turnstile.Conformance.AdapterCase do
  @moduledoc """
  The Tier 1 case template. `use Turnstile.Conformance.AdapterCase,
  adapter: Turnstile.Code, repo: Example.Repo, world: Example.World`
  defines an async test module whose setup prepares the repo for the test,
  stubs the clock, and binds the adapter through the configuration
  override, so each adapter's conformance run is its own module and all of
  them run in one `mix test`.

  The template names no schema and no rule. `world:` is a
  `Turnstile.Conformance.World`: the module that says what a population
  holds, what the rule over it allows, and how to write one through the
  seam. An adapter outside this repository points the template at its own
  tables and runs the same laws.

  The tests are the port's invariants as properties over
  `Turnstile.Conformance.Gen`, each iteration writing a population through
  the seam and, when the adapter keeps state of its own, seeding it through
  the `seed:` module; the two shape tests; the fail-closed case; and the
  revocation-latency template.

  Options:

  - `adapter:` the adapter module, required.
  - `repo:` the mediated repo the population is written through, required.
  - `world:` the `Turnstile.Conformance.World` module, required.
  - `sandbox:` a module answering `setup(repo, tags)`, called first in every
    test, for a suite whose repo needs a checkout, a transaction, or a row
    of its own before the test runs. Omit it for a repo that needs none.
  - `async:` default `true`, and `false` when `committed:` is given, since
    the committed cases truncate tables every module shares.
  - `seed:` a `Turnstile.Conformance.Seed` module, called after every
    population the template writes. Omit it for an adapter that reads the
    world's own tables.
  - `outage:` a module whose `outage/0` makes the engine unreachable for
    the rest of the test; the fail-closed case is defined when given.
  - `setup_queries:` the queries the adapter adds to every mediated call,
    counted by the shape tests; default 0.
  - `committed:` `[repo: module, owner: module, tables: [name]]`, the
    committed and owner repos and the tables to truncate; the latency case
    is defined when given.
  """

  alias Turnstile.Conformance.AdapterCase.Laws

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    config = %{
      adapter: Keyword.fetch!(opts, :adapter),
      repo: Keyword.fetch!(opts, :repo),
      world: Keyword.fetch!(opts, :world),
      sandbox: Keyword.get(opts, :sandbox),
      seed: Keyword.get(opts, :seed),
      outage: Keyword.get(opts, :outage),
      setup_queries: Keyword.get(opts, :setup_queries, 0),
      committed: Keyword.get(opts, :committed)
    }

    async = Keyword.get(opts, :async, is_nil(config.committed))

    [
      preamble(config, async),
      declaration(),
      properties(),
      shapes(),
      fail_closed(config.outage),
      latency(config.committed)
    ]
  end

  @doc false
  @spec __setup__(map(), map()) :: {:ok, keyword()}
  def __setup__(config, tags) do
    repo = if tags[:committed], do: committed_repo!(config), else: config.repo
    if config.sandbox, do: :ok = config.sandbox.setup(repo, tags)
    if tags[:committed], do: truncate!(config)
    :ok = Turnstile.Test.with_config(adapter: config.adapter, clock: &DateTime.utc_now/0)
    {:ok, adapter: config.adapter, repo: repo, case: config}
  end

  defp preamble(config, async) do
    quote do
      use ExUnit.Case, async: unquote(async)
      use ExUnitProperties

      alias Turnstile.Conformance.AdapterCase.Laws
      alias Turnstile.Conformance.Gen

      @moduletag adapter: unquote(config.adapter)
      @adapter_case unquote(Macro.escape(config))
      @conformance_world unquote(config.world)

      setup tags do
        unquote(__MODULE__).__setup__(@adapter_case, tags)
      end
    end
  end

  defp declaration do
    quote do
      test "the adapter declares its scope cap", %{adapter: adapter} do
        assert adapter.scope_cap() == :none or is_integer(adapter.scope_cap())
      end
    end
  end

  defp properties, do: [rule_agreement(), scope_fidelity(), deny_by_default()]

  defp rule_agreement do
    quote do
      property "rule agreement: the adapter answers as the world's rule does", context do
        check all(
                world <- Gen.world(@conformance_world),
                subject <- Gen.subject(world),
                operation <- Gen.operation(@conformance_world),
                object <- Gen.object(world),
                max_runs: 25
              ) do
          Laws.rule_agreement(context, world, subject, operation, object)
        end
      end
    end
  end

  defp scope_fidelity do
    quote do
      property "scope fidelity: the rows a scope admits are the objects check allows", context do
        check all(
                world <- Gen.world(@conformance_world),
                subject <- Gen.subject(world),
                operation <- Gen.operation(@conformance_world),
                max_runs: 25
              ) do
          Laws.scope_fidelity(context, world, subject, operation)
        end
      end
    end
  end

  defp deny_by_default do
    quote do
      property "deny by default: an unknown operation, subject kind, or subject is denied", context do
        check all(
                world <- Gen.world(@conformance_world),
                subjects <- Gen.strangers(world),
                operation <- Gen.unknown_operation(),
                object <- Gen.object(world),
                max_runs: 25
              ) do
          Laws.deny_by_default(context, world, subjects, operation, object)
        end
      end
    end
  end

  defp shapes do
    quote do
      test "shape: a scoped all over 1,000 rows is one query plus the adapter's own, and one record", context do
        Laws.scoped_all_shape(context)
      end

      test "shape: a single-row fact write is the write alone, and one record", context do
        Laws.fact_write_shape(context)
      end
    end
  end

  defp fail_closed(nil), do: []

  defp fail_closed(_outage) do
    quote do
      test "fail closed: an unreachable engine denies every call with engine_unreachable", context do
        Laws.fail_closed(context)
      end
    end
  end

  defp latency(nil), do: []

  defp latency(_committed) do
    quote do
      @tag :committed
      test "latency: a revocation through the seam to the first denied check, printed and never asserted", context do
        Laws.latency(context)
      end
    end
  end

  defp committed_repo!(%{committed: nil}) do
    raise ArgumentError, "a :committed test needs the committed: option of use Turnstile.Conformance.AdapterCase"
  end

  defp committed_repo!(%{committed: committed}), do: Keyword.fetch!(committed, :repo)

  defp truncate!(%{committed: committed}) do
    owner = Keyword.fetch!(committed, :owner)
    tables = Enum.join(Keyword.fetch!(committed, :tables), ", ")

    truncate = fn ->
      owner.query!("TRUNCATE #{tables} RESTART IDENTITY CASCADE")
      :ok
    end

    :ok = truncate.()
    ExUnit.Callbacks.on_exit(truncate)
  end
end
