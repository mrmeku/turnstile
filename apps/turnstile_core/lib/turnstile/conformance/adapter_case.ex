defmodule Turnstile.Conformance.AdapterCase do
  @moduledoc """
  The Tier 1 case template. `use Turnstile.Conformance.AdapterCase,
  adapter: Turnstile.Code, repo: Example.Repo` defines an async test module
  whose setup checks out the sandbox on the repo, inserts the test's counter
  row, starts a ledger for the test, stubs the clock, and binds the adapter
  through the configuration override, so each adapter's conformance run is
  its own module and all of them run in one `mix test`.

  The tests are the port's invariants as properties over
  `Turnstile.Conformance.Gen`, each iteration writing a world of the
  neutral fixture through the seam and, when the adapter keeps state of its
  own, seeding it through the `seed:` module; the shape tests, of ledger
  mode none for an adapter that admits it and of the ledger for one that
  requires it; the fail-closed case; the revocation-latency template; and
  the three projection cases.

  Options:

  - `adapter:` the adapter module, required.
  - `repo:` the sandboxed application-role repo, required.
  - `async:` default `true`, and `false` when `committed:` is given, since
    the committed cases truncate tables every module shares.
  - `ledger:` `:memory` (default: a `Turnstile.Ledger.Memory` per test),
    `:none`, or `{module, options}`. The record-then-erase and
    fold-then-replay properties need a ledger and are not defined under
    `:none`.
  - `seed:` a `Turnstile.Conformance.Seed` module, called after every
    world the template writes. Omit it for an adapter that reads the
    fixture's tables.
  - `outage:` a module whose `outage/0` makes the engine unreachable for
    the rest of the test; the fail-closed case is defined when given.
  - `setup_queries:` the queries the adapter adds to every mediated call,
    counted by the shape tests; default 0.
  - `committed:` `[repo: module, owner: module, tables: [name]]`, the
    committed and owner repos and the tables to truncate; the latency case
    and the projection cases are defined when given.
  - `projection:` a module implementing `Turnstile.Projection` and
    `Turnstile.Conformance.Projected`; the module's own `setup` must put
    its configuration struct under `:projection` in the context.
  """

  alias Turnstile.Conformance.AdapterCase.Laws
  alias Turnstile.Ledger.Memory
  alias Turnstile.Test.Clock.Mock
  alias Turnstile.Test.Sandbox

  @doc false
  defmacro __using__(opts) do
    {opts, _binding} = Code.eval_quoted(opts, [], __CALLER__)

    config = %{
      adapter: Keyword.fetch!(opts, :adapter),
      repo: Keyword.fetch!(opts, :repo),
      ledger: Keyword.get(opts, :ledger, :memory),
      seed: Keyword.get(opts, :seed),
      outage: Keyword.get(opts, :outage),
      setup_queries: Keyword.get(opts, :setup_queries, 0),
      committed: Keyword.get(opts, :committed),
      projection: Keyword.get(opts, :projection)
    }

    async = Keyword.get(opts, :async, is_nil(config.committed))

    [
      preamble(config, async),
      declaration(),
      properties(),
      ledger_properties(config.ledger),
      round_trips(),
      shapes(config),
      fail_closed(config.outage),
      latency(config.committed),
      projection(config.committed, config.projection)
    ]
  end

  @doc false
  @spec __setup__(map(), map()) :: {:ok, keyword()}
  def __setup__(config, tags) do
    repo = if tags[:committed], do: committed_repo!(config), else: config.repo
    :ok = Sandbox.setup(repo, tags)
    if tags[:committed], do: truncate!(config)
    ledger = start_ledger!(config.ledger)
    Mox.stub(Mock, :now, &DateTime.utc_now/0)
    :ok = Turnstile.Test.with_config(adapter: config.adapter, ledger: ledger, clock: Mock)
    {:ok, adapter: config.adapter, repo: repo, ledger: ledger, case: config}
  end

  defp preamble(config, async) do
    quote do
      use ExUnit.Case, async: unquote(async)
      use ExUnitProperties

      alias Turnstile.Conformance.AdapterCase.Laws
      alias Turnstile.Conformance.Gen

      @moduletag adapter: unquote(config.adapter)
      @adapter_case unquote(Macro.escape(config))

      setup tags do
        unquote(__MODULE__).__setup__(@adapter_case, tags)
      end
    end
  end

  defp declaration do
    quote do
      test "the adapter declares whether it requires a ledger and its scope cap", %{adapter: adapter} do
        assert is_boolean(adapter.requires_ledger())
        assert adapter.scope_cap() == :none or is_integer(adapter.scope_cap())
      end
    end
  end

  defp properties, do: [rule_agreement(), scope_fidelity(), deny_by_default(), batch_agreement()]

  defp rule_agreement do
    quote do
      property "rule agreement: the adapter answers as the fixture's rule does", context do
        check all(
                world <- Gen.world(),
                subject <- Gen.subject(world),
                operation <- Gen.operation(),
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
        check all(world <- Gen.world(), subject <- Gen.subject(world), operation <- Gen.operation(), max_runs: 25) do
          Laws.scope_fidelity(context, world, subject, operation)
        end
      end
    end
  end

  defp deny_by_default do
    quote do
      property "deny by default: an unknown operation, subject kind, or subject is denied", context do
        check all(
                world <- Gen.world(),
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

  defp batch_agreement do
    quote do
      property "batch agreement: batch and filter agree with check object by object", context do
        check all(
                world <- Gen.world(),
                subject <- Gen.subject(world),
                operation <- Gen.operation(),
                objects <- Gen.objects(world),
                max_runs: 25
              ) do
          Laws.batch_agreement(context, world, subject, operation, objects)
        end
      end
    end
  end

  defp ledger_properties(:none), do: []
  defp ledger_properties(_ledger), do: [record_then_erase(), fold_then_replay()]

  defp record_then_erase do
    quote do
      property "record-then-erase: a grant written and erased leaves two events, no fact, and a denial", context do
        check all(
                world <- Gen.world(),
                account <- Gen.account(world),
                folder <- Gen.folder(world),
                role <- Gen.role(),
                max_runs: 25
              ) do
          Laws.record_then_erase(context, world, account, folder, role)
        end
      end
    end
  end

  defp fold_then_replay do
    quote do
      property "fold-then-replay: the fold equals the state and the fold at t equals the state at t", context do
        check all(world <- Gen.world(), steps <- Gen.steps(world), max_runs: 25) do
          Laws.fold_then_replay(context, world, steps)
        end
      end
    end
  end

  defp round_trips do
    Enum.map(
      [
        {"decision", Turnstile.Decision, :decision},
        {"fact event", Turnstile.FactEvent, :fact_event},
        {"policy version", Turnstile.PolicyVersion, :policy_version},
        {"reason", Turnstile.Reason, :reason},
        {"subject", Turnstile.Subject, :subject}
      ],
      &round_trip/1
    )
  end

  defp round_trip({name, module, generator}) do
    quote do
      property unquote("round trip: a #{name} survives to_map and from_map") do
        check all(value <- Gen.unquote(generator)()) do
          Laws.round_trip(unquote(module), value)
        end
      end
    end
  end

  # An adapter that requires a ledger has no mode none to count a shape in,
  # so its shape is counted under the ledger the template started, and the
  # refusal of mode none is the case in place of the two mode-none ones
  # (`docs/reference.md` §7).
  defp shapes(config) do
    {:module, adapter} = Code.ensure_compiled(config.adapter)

    if adapter.requires_ledger(), do: ledger_shapes(), else: mode_none_shapes()
  end

  defp mode_none_shapes do
    quote do
      test "shape: a scoped all over 1,000 rows in mode none is one query, one record, no ledger row", context do
        Laws.scoped_all_shape(context)
      end

      test "shape: a single-row fact write in mode none is the write alone, no re-read, no ledger row", context do
        Laws.fact_write_shape(context)
      end
    end
  end

  defp ledger_shapes do
    quote do
      test "shape: a scoped all over 1,000 rows is the query and the adapter's own, one record, no ledger row", context do
        Laws.scoped_all_ledger_shape(context)
      end

      test "mode none: an adapter that requires a ledger refuses the configuration", context do
        Laws.mode_none_refused(context)
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

  defp projection(nil, _projection), do: []
  defp projection(_committed, nil), do: []

  defp projection(_committed, _projection) do
    quote do
      @tag :committed
      test "projection: one drain covers the head, its lag printed as projector_drain", context do
        Laws.projection_lag(context)
      end

      @tag :committed
      test "projection: a fact written behind the projector's back is drift reconcile reports", context do
        Laws.projection_drift(context)
      end

      @tag :committed
      test "projection: a drain interrupted before its checkpoint advances converges on the next", context do
        Laws.projection_convergence(context)
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
      owner.query!("UPDATE turnstile_ledger_counter SET position = 0 WHERE name = 'default'")
      :ok
    end

    :ok = truncate.()
    ExUnit.Callbacks.on_exit(truncate)
  end

  defp start_ledger!(:none), do: :none

  defp start_ledger!(:memory) do
    pid = ExUnit.Callbacks.start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})
    {Memory, agent: pid}
  end

  defp start_ledger!({module, options}) when is_atom(module) and is_list(options), do: {module, options}
end
