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
  alias Turnstile.Dev.Sandbox
  alias Turnstile.Error
  alias Turnstile.Fga
  alias Turnstile.Fga.Adapter.Decide
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Read
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Conformance.Population
  alias Turnstile.Fga.Drift
  alias Turnstile.Fga.TupleKey
  alias Turnstile.FgaTest.Guard
  alias Turnstile.Test
  alias Turnstile.TestRepos.Sandboxed

  @now ~U[2026-09-09 12:00:00.000000Z]

  # The adapter over a fake, with a store of the test's own, and the markers
  # and the tables in the sandboxed repo the binding names.
  setup tags do
    :ok = Sandbox.setup(Sandboxed, tags)
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "adapter")
    {:ok, model} = Fake.write_model(agent, store, %{"schema_version" => "1.1"})

    :ok = Test.with_config(adapter: {Fga, endpoint: agent, store_id: store, client: Fake, model_id: model})

    :ok = Binding.override(repo: Sandboxed, model: "priv/conformance/model.fga", mapping: Mapping)
    {:ok, options} = options()

    {:ok, agent: agent, store: store, model: model, options: options}
  end

  test "the adapter states how far one listing reaches, and settles by draining" do
    assert Fga.scope_cap() == Decide.scope_cap()
    assert Fga.scope_cap() == 1_000
    assert Fga.settle() == :ok

    schema = Fga.options_schema().schema
    assert schema[:endpoint][:required]
    assert schema[:store_id][:required]
    refute schema[:model_id][:required]
  end

  test "marking every object and settling fills the store from the tables", context do
    :ok = Population.write(Sandboxed)

    assert Fga.mark_all() == :ok
    assert Fga.settle() == :ok
    assert {:ok, drift} = Fga.reconcile()
    assert Drift.clean?(drift)
    assert %TupleKey{user: "user:acct-a", relation: "editor", object: "folder:1"} = held(context, "folder:1")
  end

  test "a rebuild is a store of its own, carrying the model and every tuple the tables require", context do
    :ok = Population.write(Sandboxed)

    assert {:ok, rebuilt} = Fga.rebuild("rebuilt")
    assert rebuilt != context.store
    assert %TupleKey{user: "user:acct-a"} = held(%{context | store: rebuilt}, "folder:1")
  end

  test "decide answers one question under the pinned model", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :allow} = allowed} =
             Fga.decide(ann(), :read, folder, environment(), context.options)

    assert allowed.reason == :allowed
    assert allowed.meta.rule == "can_read"
    assert allowed.version == context.model

    assert {:ok, %Answer{verdict: :allow}} = Fga.decide(ann(), :read, folder, environment(), context.options)
    assert {:ok, %Answer{verdict: :deny}} = Fga.decide(ann(), :edit, folder, environment(), context.options)
  end

  test "scope answers a rule over the identifiers of a type", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])

    assert {:ok, {rule, _answer}} = Fga.scope(ann(), :read, :folder, environment(), context.options)
    assert inspect(rule) == inspect(dynamic([row], row.id in ^["1"]))
  end

  test "with nothing bound no callback asks anything", context do
    Process.delete(Binding)
    folder = {:folder, 1}
    detail = "nothing bound and no override"

    assert {:error, %Error{reason: :engine_unreachable, detail: decide}} =
             Fga.decide(ann(), :read, folder, environment(), context.options)

    assert decide == "#{inspect(Fga)} failed during decide: invalid binding: #{detail}"
    assert_down(Fga.scope(ann(), :read, :folder, environment(), context.options), :scope)

    assert {:error, %Error{reason: :invalid, detail: invalid}} = Fga.mark_all()
    assert invalid == "invalid binding: #{detail}"
  end

  test "a guard the binding names is asked first, and what it refuses is denied by the guard", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    :ok = Binding.override(guard: Guard)
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :allow}} = Fga.decide(ann(), :read, folder, cleared(), context.options)

    assert {:ok, %Answer{verdict: :deny} = denied} = Fga.decide(ann(), :read, folder, environment(), context.options)
    assert denied.reason == :rule_denied
    assert denied.meta.rule == Decide.guard_rule()
    assert denied.version == context.model

    assert {:ok, {rule, %Answer{verdict: :deny}}} =
             Fga.scope(ann(), :read, :folder, environment(), context.options)

    assert inspect(rule) == inspect(dynamic([_row], false))
  end

  test "what the guard admits still needs a model pinned, and what it refuses does not", context do
    :ok = Binding.override(guard: Guard)
    options = Keyword.delete(context.options, :model_id)
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :deny, version: nil}} = Fga.decide(ann(), :read, folder, environment(), options)
    assert_down(Fga.decide(ann(), :read, folder, cleared(), options), :decide)
  end

  test "a scope above the cap records limited and check still answers each row", context do
    :ok = readable(context, 1..1_000)
    :telemetry.attach(inspect(self()), Decide.fallback_event(), &__MODULE__.forward/4, self())

    {rule, %Decision{} = decision} = Turnstile.scope(ann(), :read, :folder)

    assert inspect(rule) == inspect(dynamic([_row], false))
    assert decision.verdict == :deny
    assert decision.reason == :engine_unreachable
    assert_receive {:scope_fallback, %{count: 1_000}, %{operation: :read, type: :folder, level: :limited}}

    kept = for id <- 1..1_000, Turnstile.check(ann(), :read, {:folder, id}), do: {:folder, id}

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

  # The one tuple the store holds for an object, for a case that states there
  # is one.
  defp held(context, object) do
    [type, id] = String.split(object, ":", parts: 2)
    {:ok, page} = Fake.read(context.agent, context.store, %Read{object_type: type, object_id: id, limit: 100})

    List.first(page.tuples)
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
