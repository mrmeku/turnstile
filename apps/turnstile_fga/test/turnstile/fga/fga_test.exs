defmodule Turnstile.FgaTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Fga
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Checkpoint
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Conformance.Mapping
  alias Turnstile.Fga.Decide
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Ledger.Memory
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject
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

  test "the adapter declares that it requires a ledger and how far one listing reaches" do
    assert Fga.requires_ledger() == true
    assert Fga.scope_cap() == Decide.scope_cap()
    assert Fga.scope_cap() == 1_000

    schema = Fga.options_schema().schema
    assert schema[:endpoint][:required]
    assert schema[:store_id][:required]
    refute schema[:model_id][:required]
    assert schema[:drain_interval][:default] == 1_000
  end

  test "authorize and check answer one question under the pinned model", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    folder = %Object{type: :folder, id: 1}

    assert {:ok, %Answer{verdict: :allow} = allowed} =
             Fga.authorize(ann(), :read, folder, environment(), context.options)

    assert allowed.reason == Reason.allowed("can_read")
    assert allowed.policy_version == context.model

    assert {:ok, %Answer{verdict: :allow}} = Fga.check(ann(), :read, folder, environment(), context.options)
    assert {:ok, %Answer{verdict: :deny}} = Fga.check(ann(), :edit, folder, environment(), context.options)
  end

  test "batch, scope, and explain answer for many, for a type, and with what held", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    objects = [%Object{type: :folder, id: 1}, %Object{type: :folder, id: 2}]

    assert {:ok, answers} = Fga.batch(ann(), :read, objects, environment(), context.options)
    assert Enum.map(objects, &answers[Object.ref(&1)].verdict) == [:allow, :deny]

    assert {:ok, %Scope{rule: rule}} = Fga.scope(ann(), :read, :folder, environment(), context.options)
    assert inspect(rule) == inspect(dynamic([row], row.id in ^["1"]))

    assert {:ok, %Explanation{answer: %Answer{verdict: :allow}}} =
             Fga.explain(ann(), :read, %Object{type: :folder, id: 1}, environment(), context.options)
  end

  test "every answer carries the position the store has been drained to", context do
    folder = %Object{type: :folder, id: 1}

    assert {:ok, %Answer{applied_position: 0}} = Fga.check(ann(), :read, folder, environment(), context.options)

    :ok = Checkpoint.advance(Sandboxed, context.store, 12)

    assert {:ok, %Answer{applied_position: 12}} = Fga.check(ann(), :read, folder, environment(), context.options)
    assert {:ok, answers} = Fga.batch(ann(), :read, [folder], environment(), context.options)
    assert answers[{:folder, 1}].applied_position == 12
  end

  test "with nothing bound no callback asks anything", context do
    Process.delete(Binding)
    folder = %Object{type: :folder, id: 1}
    detail = "nothing bound and no override"

    assert {:error, %Error.Engine{operation: :authorize, detail: ^detail} = error} =
             Fga.authorize(ann(), :read, folder, environment(), context.options)

    assert error.adapter == Fga
    assert {:error, %Error.Engine{operation: :check}} = Fga.check(ann(), :read, folder, environment(), context.options)
    assert {:error, %Error.Engine{operation: :batch}} = Fga.batch(ann(), :read, [folder], environment(), context.options)
    assert {:error, %Error.Engine{operation: :scope}} = Fga.scope(ann(), :read, :folder, environment(), context.options)

    assert {:error, %Error.Engine{operation: :explain}} =
             Fga.explain(ann(), :read, folder, environment(), context.options)
  end

  test "a scope above the cap records limited and matches filter", context do
    :ok = readable(context, 1..1_000)
    :telemetry.attach(inspect(self()), Decide.fallback_event(), &__MODULE__.forward/4, self())

    {rule, %Decision{} = decision} = Turnstile.scope(ann(), :read, :folder)

    assert inspect(rule) == inspect(dynamic([_row], false))
    assert decision.verdict == :deny
    assert decision.reason.code == :engine_unreachable
    assert_receive {:scope_fallback, %{count: 1_000}, %{operation: :read, type: :folder, level: :limited}}

    kept = Turnstile.filter(ann(), :read, for(id <- 1..1_000, do: %Object{type: :folder, id: id}))

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

  defp ann, do: %Subject{id: "ann", kind: :user}

  defp environment, do: %Environment{now: @now}

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
end
