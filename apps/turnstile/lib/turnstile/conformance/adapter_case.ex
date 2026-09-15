defmodule Turnstile.Conformance.AdapterCase do
  @moduledoc """
  The Tier 1 case template. `use Turnstile.Conformance.AdapterCase,
  adapter: Turnstile.Rbac, repo: Example.Infrastructure.Repo, world: Example.World`
  defines a test module whose setup prepares the repo for the test, stubs
  the clock, and binds the adapter through the configuration override, so
  each adapter's conformance run is its own module and all of them run in
  one `mix test`.

  The template names no schema and no rule. `world:` is a
  `Turnstile.Conformance.World`: the module that says what a population
  holds, what the rule over it allows, and how to write one through the
  seam. An adapter outside this repository points the template at its own
  tables and runs the same laws.

  The tests are the laws of `docs/conformance.md` §2, each named by its id
  and its sentence from `Turnstile.Conformance.Law`, with their bodies in
  `Turnstile.Conformance.AdapterCase.Laws` and its modules; beside them,
  the scope cap declaration and the fact-write shape. Three laws are
  properties over `Turnstile.Conformance.Gen`, each iteration writing a
  population through the seam and, when the adapter keeps state of its
  own, seeding it through the `seed:` module. The fail-closed law needs
  `outage:`, the latency law needs `committed:`, and the change-management
  laws need `versions:` and `committed:` both.

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
    the rest of the test; `ac3-05` is defined when given.
  - `setup_queries:` the queries the adapter adds to every mediated call,
    counted by the shape laws; default 0.
  - `committed:` `[repo: module, owner: module, tables: [name]]`, the
    committed and owner repos and the tables to truncate; `ac2-05` is
    defined when given.
  - `versions:` a `Turnstile.Conformance.Versions` module; the `cm3` laws
    run when given and are skipped with the reason printed when not. They
    write on the committed repo, so `committed:` is required beside it.
  """

  alias Turnstile.Conformance.AdapterCase.Laws
  alias Turnstile.Conformance.Law

  @versions ~w(cm3-01 cm3-02 cm3-03 cm3-04)

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
      committed: Keyword.get(opts, :committed),
      versions: Keyword.get(opts, :versions)
    }

    if config.versions && is_nil(config.committed) do
      raise ArgumentError, "versions: needs committed: beside it, since the cm3 laws write on the committed repo"
    end

    async = Keyword.get(opts, :async, is_nil(config.committed))

    [
      preamble(config, async),
      declaration(),
      accounts(),
      access(),
      fail_closed(config.outage),
      latency(config.committed),
      audit(),
      shapes(),
      versions(config.versions)
    ]
  end

  @doc false
  @spec __setup__(map(), map()) :: {:ok, keyword()}
  def __setup__(config, tags) do
    repo = if tags[:committed], do: committed_repo!(config), else: config.repo
    if config.sandbox, do: :ok = config.sandbox.setup(repo, tags)
    if tags[:committed], do: truncate!(config)
    :ok = Turnstile.Test.with_config(adapter: config.adapter, clock: &DateTime.utc_now/0)
    :ok = setup_versions(config.versions, tags)
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

  defp accounts, do: [account_facts(), account_review()]

  defp account_facts do
    quote do
      test unquote(Law.name("ac2-01")), context do
        Laws.Accounts.account_changes(context)
      end

      test unquote(Law.name("ac2-02")), context do
        Laws.Accounts.expiry(context)
      end

      test unquote(Law.name("ac2-03")), context do
        Laws.Accounts.disqualified(context)
      end
    end
  end

  defp account_review do
    quote do
      property unquote(Law.name("ac2-04")), context do
        check all(
                world <- Gen.world(@conformance_world),
                operation <- Gen.operation(@conformance_world),
                max_runs: 25
              ) do
          Laws.Accounts.review(context, world, operation)
        end
      end

      test unquote(Law.name("ac6-01")), context do
        Laws.Accounts.privileged_denied(context)
      end
    end
  end

  defp access, do: [rule_agreement(), deny_by_default(), scope_fidelity(), scoped_all_shape()]

  defp rule_agreement do
    quote do
      property unquote(Law.name("ac3-01")), context do
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

  defp deny_by_default do
    quote do
      property unquote(Law.name("ac3-02")), context do
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

  defp scope_fidelity do
    quote do
      property unquote(Law.name("ac3-03")), context do
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

  defp scoped_all_shape do
    quote do
      test unquote(Law.name("ac3-04")), context do
        Laws.scoped_all_shape(context)
      end
    end
  end

  defp fail_closed(nil), do: []

  defp fail_closed(_outage) do
    quote do
      test unquote(Law.name("ac3-05")), context do
        Laws.fail_closed(context)
      end
    end
  end

  defp latency(nil), do: []

  defp latency(_committed) do
    quote do
      @tag :committed
      test unquote(Law.name("ac2-05")), context do
        Laws.latency(context)
      end
    end
  end

  defp audit, do: [audit_events(), audit_content(), audit_seam(), audit_refusals()]

  defp audit_events do
    quote do
      test unquote(Law.name("au2-01")), context do
        Laws.Audit.decision_events(context)
      end

      test unquote(Law.name("au2-02")), context do
        Laws.Audit.denial_reason(context)
      end

      test unquote(Law.name("au2-03")), context do
        Laws.Audit.scoped_verdicts(context)
      end
    end
  end

  defp audit_content do
    quote do
      test unquote(Law.name("au3-01")), context do
        Laws.Audit.no_attribute_value(context)
      end

      test unquote(Law.name("au3-02")), context do
        Laws.Audit.change_event(context)
      end

      test unquote(Law.name("au3-03")), context do
        Laws.Audit.access_event(context)
      end

      test unquote(Law.name("au3-04")), context do
        Laws.Audit.one_operation(context)
      end
    end
  end

  defp audit_seam do
    quote do
      test unquote(Law.name("au12-01")), context do
        Laws.Audit.inside_transaction(context)
      end

      test unquote(Law.name("au12-02")), context do
        Laws.Audit.bulk_refused(context)
      end

      test unquote(Law.name("au12-03")), context do
        Laws.Audit.around_seam(context)
      end
    end
  end

  defp audit_refusals do
    quote do
      test unquote(Law.name("au12-04")), context do
        Laws.Audit.refused_write(context)
      end

      test unquote(Law.name("au12-05")), context do
        Laws.Audit.unmediated_refused(context)
      end

      test unquote(Law.name("au12-06")), context do
        Laws.Audit.mediated_reads(context)
      end
    end
  end

  defp shapes do
    quote do
      test "shape: a single-row fact write is the write alone, and one record", context do
        Laws.fact_write_shape(context)
      end
    end
  end

  defp versions(nil) do
    for id <- @versions do
      quote do
        @tag skip: "the template was given no versions: module, so #{unquote(id)} has nothing to publish"
        test unquote(Law.name(id)), _context do
          :ok
        end
      end
    end
  end

  defp versions(_versions) do
    quote do
      @tag :committed
      test unquote(Law.name("cm3-01")), context do
        Laws.Versions.publish(context)
      end

      @tag :committed
      test unquote(Law.name("cm3-02")), context do
        Laws.Versions.version_reported(context)
      end

      @tag :committed
      test unquote(Law.name("cm3-03")), context do
        Laws.Versions.tightened_artifact(context)
      end

      @tag :committed
      test unquote(Law.name("cm3-04")), context do
        Laws.Versions.propagation(context)
      end
    end
  end

  defp setup_versions(nil, _tags), do: :ok

  defp setup_versions(versions, tags) do
    if Code.ensure_loaded?(versions) and function_exported?(versions, :setup, 1), do: versions.setup(tags), else: :ok
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
