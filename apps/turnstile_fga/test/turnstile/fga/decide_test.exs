defmodule Turnstile.Fga.DecideTest do
  use ExUnit.Case, async: true

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Error
  alias Turnstile.Fga.Client.BatchCheck
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.Fake
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Write
  alias Turnstile.Fga.Decide
  alias Turnstile.Fga.TupleKey

  @now ~U[2026-09-09 12:00:00.000000Z]

  # A fake on an agent of the test's own answers from its tuples, which is
  # what these cases are about: the request each callback sends and the
  # answer it makes of the reply. What a model composes is a server's, and
  # the conformance run asks one.
  setup do
    agent = start_supervised!(Fake)
    {:ok, store} = Fake.create_store(agent, "decide")
    {:ok, model} = Fake.write_model(agent, store, %{"schema_version" => "1.1"})
    options = [client: Fake, endpoint: agent, store_id: store, model_id: model]
    {:ok, entry} = Decide.entry(options, :check, %{now: @now})

    {:ok, agent: agent, store: store, model: model, options: options, entry: Decide.applied(entry, 7)}
  end

  test "an operation is a relation, a subject is a user, and an object is one of the store" do
    assert Decide.relation(:read) == "can_read"
    assert Decide.relation(:edit) == "can_edit"
    assert Decide.user({:user, "ann"}) == "user:ann"
    assert Decide.user({:non_person_entity, "importer"}) == "user:importer"
    assert Decide.named({:folder, 1}) == "folder:1"
    assert Decide.time_fact() == "current_time"
    assert Decide.scope_cap() == 1_000
    assert Decide.fallback_event() == [:turnstile, :fga, :scope_fallback]
  end

  test "the entry is what the configuration names, and an entry naming less is an engine error", context do
    assert context.entry.client == Fake
    assert context.entry.endpoint == context.agent
    assert context.entry.store == context.store
    assert context.entry.model == context.model
    assert context.entry.applied == 7

    for field <- [:endpoint, :store_id] do
      thin = Keyword.delete(context.options, field)

      assert {:error, %Error{reason: :engine_unreachable} = error} = Decide.entry(thin, :check, %{now: @now})

      assert error.detail ==
               "#{inspect(Turnstile.Fga)} failed during check: the configuration entry names no #{field}"
    end
  end

  test "a client without a client named is the client over HTTP", context do
    {:ok, entry} = Decide.entry(Keyword.delete(context.options, :client), :check, %{now: @now})

    assert entry.client == Turnstile.Fga.Client.Http
    assert entry.applied == nil
  end

  test "the context is the caller's facts under their own names and the moment under current_time", context do
    facts = %{clearance: "cleared", from: ~D[2026-01-01], seen: ~N[2026-01-02 03:04:05], count: 3}
    {:ok, entry} = Decide.entry(context.options, :check, Map.put(facts, :now, @now))

    assert {:ok, %Answer{}} = Decide.one(entry, ann(), :read, {:folder, 1})

    assert [%Check{} = request] = requests(context.agent, :check)

    assert request.context == %{
             "current_time" => "2026-09-09T12:00:00.000000Z",
             "clearance" => "cleared",
             "from" => "2026-01-01",
             "seen" => "2026-01-02T03:04:05",
             "count" => 3
           }
  end

  test "a decision asks for the higher consistency and a listing for the lower one", context do
    assert Decide.consistency(:authorize) == :higher_consistency
    assert Decide.consistency(:check) == :higher_consistency
    assert Decide.consistency(:batch) == :higher_consistency
    assert Decide.consistency(:explain) == :higher_consistency
    assert Decide.consistency(:scope) == :minimize_latency

    assert {:ok, %Answer{}} = Decide.one(context.entry, ann(), :read, {:folder, 1})
    assert [%Check{consistency: :higher_consistency, model: model}] = requests(context.agent, :check)
    assert model == context.model

    {:ok, listing} = Decide.entry(context.options, :scope, %{now: @now})
    assert {:ok, {_rule, %Answer{}}} = Decide.scoped(listing, ann(), :read, :folder)

    assert [%ListObjects{consistency: :minimize_latency, user: "user:ann", relation: "can_read", type: "folder"}] =
             requests(context.agent, :list_objects)
  end

  test "an allowance names the relation that allowed and a denial is denied by default", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])

    assert {:ok, %Answer{} = allowed} = Decide.one(context.entry, ann(), :read, {:folder, 1})
    assert allowed.verdict == :allow
    assert allowed.reason == :allowed
    assert allowed.meta.rule == "can_read"
    assert allowed.version == context.model
    assert allowed.meta.applied == 7

    assert {:ok, %Answer{} = denied} = Decide.one(context.entry, ann(), :read, {:folder, 2})
    assert denied.verdict == :deny
    assert denied.reason == :deny_by_default
    assert denied.version == context.model
    assert denied.meta.applied == 7
  end

  test "an entry that pins no model asks nothing at all", context do
    {:ok, entry} = Decide.entry(Keyword.delete(context.options, :model_id), :authorize, %{now: @now})
    folder = {:folder, 1}
    detail = "the configuration entry pins no model, so no question can be asked under one"

    assert {:error, %Error{reason: :engine_unreachable, detail: asked}} = Decide.one(entry, ann(), :read, folder)
    assert asked == "#{inspect(Turnstile.Fga)} failed during authorize: #{detail}"
    assert_pinned(Decide.many(entry, ann(), :read, [folder]), detail)
    assert_pinned(Decide.scoped(entry, ann(), :read, :folder), detail)
    assert_pinned(Decide.explained(entry, ann(), :read, folder), detail)
    assert Fake.calls(context.agent) == [{:create_store, "decide"}, {:write_model, %{"schema_version" => "1.1"}}]
  end

  test "a batch of sixty questions is one call of fifty and one of ten", context do
    objects = for id <- 1..60, do: {:folder, id}
    :ok = write(context, [tuple("ann", "can_read", "folder:7"), tuple("ann", "can_read", "folder:55")])

    assert {:ok, answers} = Decide.many(context.entry, ann(), :read, objects)
    assert map_size(answers) == 60
    assert answers[{:folder, 7}].verdict == :allow
    assert answers[{:folder, 55}].verdict == :allow
    assert answers[{:folder, 8}].verdict == :deny
    assert answers[{:folder, 7}].version == context.model

    assert [%BatchCheck{} = first, %BatchCheck{} = second] = requests(context.agent, :batch_check)
    assert Enum.map(first.checks, &elem(&1, 0)) == for(index <- 0..49, do: "c-#{index}")
    assert Enum.map(second.checks, &elem(&1, 0)) == for(index <- 0..9, do: "c-#{index}")
    assert first.consistency == :higher_consistency
  end

  test "a scope under the cap is the identifiers of the listing as a rule over rows", context do
    {:ok, entry} = Decide.entry(context.options, :scope, %{now: @now})
    :ok = write(context, [tuple("ann", "can_read", "folder:1"), tuple("ann", "can_read", "folder:2")])

    assert {:ok, {rule, %Answer{} = answer}} = Decide.scoped(entry, ann(), :read, :folder)
    assert inspect(rule) == inspect(dynamic([row], row.id in ^["1", "2"]))
    assert answer.verdict == :allow
    assert answer.reason == :allowed
    assert answer.meta.rule == "can_read"
    assert answer.version == context.model
  end

  test "an explanation of a denial names nothing that held", context do
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :deny, meta: %{matched: []}}} =
             Decide.explained(context.entry, ann(), :read, folder)

    assert requests(context.agent, :expand) == []
  end

  test "an explanation of an allowance asks the tree and which of its branches hold", context do
    :ok = write(context, [tuple("ann", "can_read", "folder:1")])
    folder = {:folder, 1}

    assert {:ok, %Answer{verdict: :allow, meta: %{matched: []}}} =
             Decide.explained(context.entry, ann(), :read, folder)

    assert [request] = requests(context.agent, :expand)
    assert request.relation == "can_read"
    assert request.object == "folder:1"
    assert request.model == context.model
  end

  test "an engine error on the way to the server is the answer, whichever callback asked", context do
    absent = Keyword.put(context.options, :store_id, "store-404")
    {:ok, entry} = Decide.entry(absent, :batch, %{now: @now})
    folder = {:folder, 1}

    assert {:error, %Error{reason: :engine_unreachable, detail: "Turnstile.Fga failed during check" <> _rest}} =
             Decide.one(entry, ann(), :read, folder)

    assert {:error, %Error{reason: :engine_unreachable, detail: "Turnstile.Fga failed during batch_check" <> _rest}} =
             Decide.many(entry, ann(), :read, [folder])

    assert {:error, %Error{reason: :engine_unreachable, detail: "Turnstile.Fga failed during list_objects" <> _rest}} =
             Decide.scoped(entry, ann(), :read, :folder)

    assert {:error, %Error{reason: :engine_unreachable, detail: "Turnstile.Fga failed during check" <> _rest}} =
             Decide.explained(entry, ann(), :read, folder)
  end

  # Every callback refuses the same way when the entry pins no model.
  defp assert_pinned(result, detail) do
    assert {:error, %Error{reason: :engine_unreachable, detail: said}} = result
    assert said =~ detail
  end

  defp ann, do: {:user, "ann"}

  defp tuple(user, relation, object), do: %TupleKey{user: "user:#{user}", relation: relation, object: object}

  defp write(context, tuples) do
    {:ok, _count} = Fake.write(context.agent, context.store, %Write{deletes: [], writes: tuples})

    :ok
  end

  defp requests(agent, operation) do
    for {^operation, request} <- Fake.calls(agent), do: request
  end
end
