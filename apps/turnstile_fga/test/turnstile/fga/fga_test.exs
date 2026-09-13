defmodule Turnstile.FgaTest.Guard do
  @moduledoc false
  @behaviour Turnstile.Fga.Guard

  @impl Turnstile.Fga.Guard
  def admits?(:read, environment), do: Map.get(environment, :cleared) == true
  def admits?(_operation, %{now: _now}), do: true
end

defmodule Turnstile.FgaTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Checkpoint
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Decide
  alias Turnstile.Fga.Projector
  alias Turnstile.Fga.TupleKey
  alias Turnstile.FgaTest.Guard
  alias Turnstile.Ledger.Memory
  alias Turnstile.Test
  alias Turnstile.Test.Sandbox
  alias Turnstile.TestRepos.Sandboxed

  @now ~U[2026-09-09 12:00:00.000000Z]

  # The adapter over a fake, with a store of the test's own and the checkpoint
  # in the sandboxed repo the binding names, which is where the position every
  # answer carries is read.
  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "adapter")
    {:ok, model} = Fake.write_model(agent, store, %{"schema_version" => "1.1"})
    ledger = start_supervised!(%{id: Memory, start: {Memory, :start_link, []}})

    :ok =
      Test.with_config(
        adapter: {Fga, endpoint: agent, store_id: store, client: Fake, model_id: model},
        ledger: {Memory, agent: ledger}
      )

    :ok = Binding.override(repo: Sandboxed, model: "priv/conformance/model.fga", mapping: Mapping)
    {:ok, options} = options()

    {:ok, agent: agent, store: store, model: model, options: options}
  end

  test "the adapter declares a ledger, how far one listing reaches, and its projection", context do
    assert Fga.requires_ledger() == true
    assert Fga.scope_cap() == Decide.scope_cap()
    assert Fga.scope_cap() == 1_000

    assert {:ok, {Projector, %Projector{} = projector}} = Fga.projection()
    assert projector.store == context.store
    assert projector.repo == Sandboxed

    schema = Fga.options_schema().schema
    assert schema[:endpoint][:required]
    assert schema[:store_id][:required]
    refute schema[:model_id][:required]
    assert schema[:drain_interval][:default] == 1_000
  end

  test "authorize and check answer one question under the pinned model", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :allow} = allowed} =
             Fga.authorize(ann(), :read, folder, environment(), context.options)

    assert allowed.reason == :allowed
    assert allowed.meta.rule == "can_read"
    assert allowed.version == context.model

    assert {:ok, %Answer{verdict: :allow}} = Fga.check(ann(), :read, folder, environment(), context.options)
    assert {:ok, %Answer{verdict: :deny}} = Fga.check(ann(), :edit, folder, environment(), context.options)
  end

  test "batch, scope, and explain answer for many, for a type, and with what held", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    objects = [{:folder, 1}, {:folder, 2}]

    assert {:ok, answers} = Fga.batch(ann(), :read, objects, environment(), context.options)
    assert Enum.map(objects, &answers[&1].verdict) == [:allow, :deny]

    assert {:ok, {rule, _answer}} = Fga.scope(ann(), :read, :folder, environment(), context.options)
    assert inspect(rule) == inspect(dynamic([row], row.id in ^["1"]))

    assert {:ok, %Answer{verdict: :allow}} =
             Fga.explain(ann(), :read, {:folder, 1}, environment(), context.options)
  end

  test "every answer carries the position the store has been drained to", context do
    folder = {:folder, 1}

    assert {:ok, %Answer{meta: %{applied: 0}}} = Fga.check(ann(), :read, folder, environment(), context.options)

    :ok = Checkpoint.advance(Sandboxed, context.store, 12)

    assert {:ok, %Answer{meta: %{applied: 12}}} = Fga.check(ann(), :read, folder, environment(), context.options)
    assert {:ok, answers} = Fga.batch(ann(), :read, [folder], environment(), context.options)
    assert answers[{:folder, 1}].meta.applied == 12
  end

  test "with nothing bound no callback asks anything", context do
    Process.delete(Binding)
    folder = {:folder, 1}
    detail = "nothing bound and no override"

    assert {:error, %Error{reason: :engine_unreachable, detail: authorize}} =
             Fga.authorize(ann(), :read, folder, environment(), context.options)

    assert authorize == "#{inspect(Fga)} failed during authorize: invalid binding: #{detail}"
    assert_down(Fga.check(ann(), :read, folder, environment(), context.options), :check)
    assert_down(Fga.batch(ann(), :read, [folder], environment(), context.options), :batch)
    assert_down(Fga.scope(ann(), :read, :folder, environment(), context.options), :scope)
    assert_down(Fga.explain(ann(), :read, folder, environment(), context.options), :explain)

    assert {:error, %Error{reason: :invalid, detail: invalid}} = Fga.projection()
    assert invalid == "invalid binding: #{detail}"
  end

  test "a guard the binding names is asked first, and what it refuses is denied by the guard", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    :ok = Binding.override(guard: Guard)
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :allow}} = Fga.check(ann(), :read, folder, cleared(), context.options)

    assert {:ok, %Answer{verdict: :deny} = denied} = Fga.check(ann(), :read, folder, environment(), context.options)
    assert denied.reason == :rule_denied
    assert denied.meta.rule == Decide.guard_rule()
    assert denied.version == context.model
    assert denied.meta.applied == 0

    assert {:ok, %Answer{verdict: :deny}} = Fga.authorize(ann(), :read, folder, environment(), context.options)
    assert {:ok, answers} = Fga.batch(ann(), :read, [folder], environment(), context.options)
    assert answers[{:folder, 1}].verdict == :deny

    assert {:ok, {rule, %Answer{verdict: :deny}}} =
             Fga.scope(ann(), :read, :folder, environment(), context.options)

    assert inspect(rule) == inspect(dynamic([_row], false))

    assert {:ok, %Answer{verdict: :deny, meta: %{matched: []}}} =
             Fga.explain(ann(), :read, folder, environment(), context.options)
  end

  test "what the guard admits still needs a model pinned, and what it refuses does not", context do
    :ok = Binding.override(guard: Guard)
    options = Keyword.delete(context.options, :model_id)
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :deny, version: nil}} = Fga.check(ann(), :read, folder, environment(), options)
    assert_down(Fga.check(ann(), :read, folder, cleared(), options), :check)
  end

  test "a scope above the cap records limited and matches filter", context do
    :ok = readable(context, 1..1_000)
    :telemetry.attach(inspect(self()), Decide.fallback_event(), &__MODULE__.forward/4, self())

    {rule, %Decision{} = decision} = Turnstile.scope(ann(), :read, :folder)

    assert inspect(rule) == inspect(dynamic([_row], false))
    assert decision.verdict == :deny
    assert decision.reason == :engine_unreachable
    assert_receive {:scope_fallback, %{count: 1_000}, %{operation: :read, type: :folder, level: :limited}}

    kept = Turnstile.filter(ann(), :read, for(id <- 1..1_000, do: {:folder, id}))

    assert length(kept) == 1_000
    assert Enum.sort(Enum.map(kept, &Decide.named/1)) == Enum.sort(listed(context))
  after
    :telemetry.detach(inspect(self()))
  end

  @doc false
  @spec forward([atom()], map(), map(), pid()) :: :ok
  def forward(_event, measurements, metadata, pid) do
    send(pid, {:scope_fallback, measurements, metadata})
    :ok
  end

  defp options do
    {:ok, config} = Config.resolve()
    {Fga, options} = Config.adapter(config)

    {:ok, options}
  end

  defp ann, do: {:user, "ann"}

  defp environment, do: %{now: @now}

  defp cleared, do: %{now: @now, cleared: true}

  defp tuple(user, relation, object), do: %TupleKey{user: "user:#{user}", relation: relation, object: object}

  defp write(context, tuples) do
    {:ok, _count} = Fake.write(context.agent, context.store, %Write{deletes: [], writes: tuples})

    :ok
  end

  # More folders than one listing answers with, written in calls of the size
  # one call may carry.
  defp readable(context, ids) do
    ids
    |> Enum.map(&tuple("ann", "can_read", "folder:#{&1}"))
    |> Enum.chunk_every(Client.max_tuples_per_write())
    |> Enum.each(&write(context, &1))
  end

  defp listed(context) do
    request = %ListObjects{user: "user:ann", relation: "can_read", type: "folder"}
    {:ok, objects} = Fake.list_objects(context.agent, context.store, request)

    objects
  end

  # A callback that cannot reach the engine answers the same error, naming itself.
  defp assert_down(result, operation) do
    assert {:error, %Error{reason: :engine_unreachable, detail: detail}} = result
    assert detail =~ "during #{operation}"
  end
end
