defmodule Turnstile.Conformance.AdapterCase.Laws.Audit do
  @moduledoc """
  The bodies of the audit laws, `au2`, `au3`, and `au12`: what a decision
  event and a change event carry, and what the seam records or refuses of
  a write. Each is a function of the test context, as
  `Turnstile.Conformance.AdapterCase.Laws` describes.
  """

  import ExUnit.Assertions

  alias Turnstile.Change
  alias Turnstile.Conformance.AdapterCase.Laws
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Test

  @stamped ~w(subject subject_kind operation object verdict reason version operation_id time)a

  @doc """
  `au2-01`: an allowed authorize and check for the user, and a denied check
  and authorize for the privileged subject of the same account, are four
  decision events, each carrying every field the law names.
  """
  @spec decision_events(Laws.context()) :: true
  def decision_events(%{case: %{world: module}} = context) do
    {_world, {kind, account} = subject, _grantable, object, operation} = Laws.granted_focus(context, module)
    privileged = {:privileged, account}

    {_results, events} = Laws.recorded(fn -> four_decisions(subject, privileged, operation, object) end)
    assert_four(events, [subject, subject, privileged, privileged], [kind, kind, :privileged, :privileged])
  end

  @doc "`au2-02`: the event of a denial carries the reason the error names."
  @spec denial_reason(Laws.context()) :: true
  def denial_reason(%{case: %{world: module}} = context) do
    {_world, {_kind, account}, _grantable, object, operation} = Laws.granted_focus(context, module)

    {answer, events} = Laws.recorded(fn -> Turnstile.authorize({:privileged, account}, operation, object) end)

    assert {:error, %Error{reason: reason}} = answer
    assert [%{verdict: :deny, reason: ^reason}] = events
    assert reason in Error.reasons()
  end

  @doc "`au2-03`: a scope, and a review of one subject, are three decision events whose verdict is `:scoped`."
  @spec scoped_verdicts(Laws.context()) :: true
  def scoped_verdicts(%{case: %{world: module}} = context) do
    {_world, subject, _grantable, {type, _id}, operation} = Laws.granted_focus(context, module)

    {{scope, review}, events} =
      Laws.recorded(fn ->
        {Turnstile.scope(subject, operation, type), Turnstile.review(subject, [subject], operation, type)}
      end)

    assert {_rule, %Decision{verdict: :scoped}} = scope
    assert %{^subject => {_rule, %Decision{verdict: :scoped}}} = review
    assert length(events) == 3
    assert Enum.all?(events, &(&1.verdict == :scoped))
  end

  @doc """
  `au3-01`: no value the world's rule reads appears in the decision events
  of an allowed authorize, a denied check, and a scope. The scope's event
  carries the rule where the object goes, and the rule is the policy's
  own text rather than a value read from a row, so it is left out of the
  comparison.
  """
  @spec no_attribute_value(Laws.context()) :: :ok
  def no_attribute_value(%{case: %{world: module}} = context) do
    {world, {_kind, account} = subject, _grantable, object, operation} = Laws.granted_focus(context, module)
    facts = module.facts(world)
    assert facts != [], "#{inspect(module)}.facts/1 names no value the rule reads"

    {_results, events} = Laws.recorded(fn -> three_decisions(subject, {:privileged, account}, operation, object) end)

    assert length(events) == 3
    for event <- events, fact <- facts, do: refute_carried(event, fact)
    :ok
  end

  @doc """
  `au3-02`: the event of a grant written carries every fact column from
  nothing to its value, and the event of the same grant revoked carries
  each from that value to nothing, both stamped with what the law names.
  """
  @spec change_event(Laws.context()) :: true
  def change_event(%{repo: repo, case: %{world: module}} = context) do
    {world, create} = one_grant(context, module)
    assert_change(create, :create)
    assert_from_nothing(create.changes)

    {subject, grantable} = module.focus(world)
    {_world, deleted} = Test.changes(fn -> module.revoke(repo, world, subject, grantable) end)
    assert [delete] = deleted
    assert_change(delete, :delete)
    assert delete.target == create.target
    assert delete.changes == reversed(create.changes)
  end

  @doc "`au12-01`: the change event of a grant written is published while the repo is in the write's transaction."
  @spec inside_transaction(Laws.context()) :: :ok
  def inside_transaction(%{repo: repo, case: %{world: module}} = context) do
    world = module.ungranted()
    :ok = Laws.populate(context, world)
    {subject, grantable} = module.focus(world)
    handler = {__MODULE__, make_ref()}
    :ok = :telemetry.attach(handler, Change.event(), &__MODULE__.__transaction__/4, %{pid: self(), repo: repo})

    try do
      refute repo.in_transaction?()
      _world = module.insert_grant(repo, world, subject, grantable, [])
      assert_received {:change_published, in_transaction?}
      assert in_transaction?, "the change event was published outside the write's transaction"
    after
      :telemetry.detach(handler)
    end

    :ok
  end

  @doc "`au12-02`: every bulk write to the grant's schema raises, publishes nothing, and leaves the count as it was."
  @spec bulk_refused(Laws.context()) :: true
  def bulk_refused(%{repo: repo, case: %{world: module}} = context) do
    {_world, %{schema: schema} = create} = one_grant(context, module)
    exemption = module.exemption()
    [{column, {nil, value}} | _rest] = Map.to_list(create.changes)
    counted = repo.aggregate(schema, :count, turnstile: exemption)

    calls = [
      {:update_all, [schema, [set: [{column, value}]], [turnstile: exemption]]},
      {:delete_all, [schema, [turnstile: exemption]]},
      {:insert_all, [schema, [%{column => value}], [turnstile: exemption]]}
    ]

    {:ok, events} = Test.changes(fn -> Enum.each(calls, &assert_bulk(repo, &1)) end)
    assert events == []
    assert repo.aggregate(schema, :count, turnstile: exemption) == counted
  end

  @doc "`au12-03`: a statement written by hand deletes the grant's row and publishes nothing."
  @spec around_seam(Laws.context()) :: true
  def around_seam(%{repo: repo, case: %{world: module}} = context) do
    {_world, %{schema: schema, target: {_type, id}}} = one_grant(context, module)
    exemption = module.exemption()
    [key] = schema.__schema__(:primary_key)
    statement = "DELETE FROM #{schema.__schema__(:source)} WHERE #{key} = $1"

    {_result, events} = Test.changes(fn -> repo.query!(statement, [id], turnstile: exemption) end)
    assert events == []
    assert repo.get(schema, id, turnstile: exemption) == nil
  end

  @doc "`au12-04`: a second grant of the same pair is a write the database refuses, with no row and no event."
  @spec refused_write(Laws.context()) :: true
  def refused_write(%{repo: repo, case: %{world: module}} = context) do
    {world, %{schema: schema}} = one_grant(context, module)
    {subject, grantable} = module.focus(world)
    exemption = module.exemption()
    counted = repo.aggregate(schema, :count, turnstile: exemption)

    {_error, events} =
      Test.changes(fn ->
        assert_raise Ecto.ConstraintError, fn -> module.insert_grant(repo, world, subject, grantable, []) end
      end)

    assert events == []
    assert repo.aggregate(schema, :count, turnstile: exemption) == counted
  end

  @doc "`au12-05`: a read and a write of each protected schema with no mediation raise `:unmediated`."
  @spec unmediated_refused(Laws.context()) :: :ok
  def unmediated_refused(%{repo: repo, case: %{world: module}}) do
    Enum.each(module.schemas(), fn schema ->
      read = assert_raise(Error, fn -> repo.all(schema) end)
      assert read.reason == :unmediated
      write = assert_raise(Error, fn -> repo.insert!(struct(schema)) end)
      assert write.reason == :unmediated
    end)
  end

  @doc false
  @spec __transaction__([atom()], map(), map(), map()) :: :ok
  def __transaction__(_event, _measurements, _payload, %{pid: pid, repo: repo}) do
    if self() == pid, do: send(pid, {:change_published, repo.in_transaction?()})
    :ok
  end

  # The ungranted world written and its focus granted through the seam:
  # the world the grant left, and the one change event the grant was.
  defp one_grant(%{repo: repo} = context, module) do
    world = module.ungranted()
    :ok = Laws.populate(context, world)
    {subject, grantable} = module.focus(world)
    {granted, events} = Test.changes(fn -> module.insert_grant(repo, world, subject, grantable, []) end)
    assert [create] = events
    {granted, create}
  end

  defp four_decisions(subject, privileged, operation, object) do
    assert {:ok, %Decision{}} = Turnstile.authorize(subject, operation, object)
    assert Turnstile.check(subject, operation, object)
    refute Turnstile.check(privileged, operation, object)
    assert {:error, %Error{}} = Turnstile.authorize(privileged, operation, object)
  end

  defp three_decisions(subject, privileged, operation, {type, _id} = object) do
    assert {:ok, %Decision{}} = Turnstile.authorize(subject, operation, object)
    refute Turnstile.check(privileged, operation, object)
    assert {_rule, %Decision{verdict: :scoped}} = Turnstile.scope(subject, operation, type)
  end

  defp refute_carried(event, fact) do
    inspected = inspect(Map.delete(event, :object))
    refute inspected =~ inspect(fact), "the decision event carries #{inspect(fact)}: #{inspected}"
  end

  defp assert_four(events, subjects, kinds) do
    assert length(events) == 4
    Enum.each(events, &assert_stamped/1)
    assert Enum.map(events, & &1.subject) == subjects
    assert Enum.map(events, & &1.subject_kind) == kinds
    assert Enum.map(events, & &1.verdict) == [:allow, :allow, :deny, :deny]
  end

  defp assert_stamped(event) do
    Enum.each(@stamped, fn key ->
      refute is_nil(Map.fetch!(event, key)), "the decision event carries no #{key}: #{inspect(event)}"
    end)
  end

  defp assert_change(event, operation) do
    assert event.operation == operation
    assert is_atom(event.kind)
    assert {type, _id} = event.target
    assert is_atom(type)
    assert {kind, _id} = event.actor
    assert event.actor_kind == kind
    assert %DateTime{} = event.time
    assert is_binary(event.operation_id)
    assert is_atom(event.schema)
  end

  defp assert_from_nothing(changes) do
    assert map_size(changes) > 0

    Enum.each(changes, fn {column, change} ->
      assert {nil, _value} = change, "#{column} was #{inspect(change)}"
    end)
  end

  defp reversed(changes), do: Map.new(changes, fn {column, {nil, value}} -> {column, {value, nil}} end)

  defp assert_bulk(repo, {name, args}) do
    error = assert_raise(Error, fn -> apply(repo, name, args) end)
    assert Exception.message(error) =~ "bulk write to an audited schema"
  end
end
