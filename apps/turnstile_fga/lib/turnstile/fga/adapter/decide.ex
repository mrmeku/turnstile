defmodule Turnstile.Fga.Adapter.Decide do
  @moduledoc false
  # The answers the adapter gives: an operation becomes a relation, a subject
  # and an object become the two ends of a tuple, and the server answers
  # whether a path joins them.
  #
  # An operation is the relation `can_` and its name, which is the one
  # translation this package makes, and a subject is a user of the store
  # whatever kind it carries, because a graph compares by walking rather than
  # by equality. An allowance names that relation as the rule that allowed. A
  # denial is denied by default: a graph has no rule that denies, it has no
  # path, and saying a rule denied would name something that does not exist.
  #
  # The environment is the context every call carries, which is what a
  # condition on a tuple is evaluated against: the caller's facts under their
  # own names, and the moment of the call under `current_time`, the one name
  # this package reserves. A condition that compares a date on a tuple with
  # the present therefore needs nothing of the caller.
  #
  # An entry is where the question goes and what it is asked under: the client,
  # the endpoint, the store, the model, and that context. Every answer carries
  # the model as its policy version. The consistency of each call is a constant
  # of this package: a decision asks for the higher consistency, so a tuple a
  # drain has written is not missed, and a listing asks for the lower one,
  # since a scope is a filter over rows the caller reads anyway.
  #
  # A scope is one `ListObjects`: under the cap its identifiers become the
  # rule, and at
  # the cap or above it the answer is short of the truth without saying so, so
  # this module emits `fallback_event/0` with the level `limited` and fails,
  # and the caller asks per page instead.
  #
  # A guard is a rule outside the graph. Where the binding names one and it
  # does not admit the operation, this module answers the denial and asks
  # nothing, and that denial names the guard as the rule that denied, because
  # something denied it rather than nothing allowing it.
  #
  # An operation the model has no relation for is a question the server
  # refuses, and that refusal is answered as it stands rather than turned into
  # a denial of this module's own, because nothing here can tell an operation
  # no one declared from a model that was published wrong. Either way the
  # caller denies.

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Error
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Consistency
  alias Turnstile.Fga.TupleKey

  @fallback [:turnstile, :fga, :scope_fallback]
  @guard "guard"
  @scope_cap 1_000
  @time "current_time"

  @typedoc "Where a question goes and what it is asked under."
  @type entry :: %{
          callback: atom(),
          client: module(),
          endpoint: Client.endpoint(),
          store: Client.store(),
          model: Client.model() | nil,
          context: map()
        }

  @doc "The telemetry event a scope at the cap emits, once per scope that falls back."
  @spec fallback_event() :: [atom()]
  def fallback_event, do: @fallback

  @doc "The rule a refusal names, which is the guard rather than anything of the model."
  @spec guard_rule() :: String.t()
  def guard_rule, do: @guard

  @doc "How many objects one `ListObjects` answers with, the pinned server's own limit."
  @spec scope_cap() :: pos_integer()
  def scope_cap, do: @scope_cap

  @doc "The name the moment of the call carries in the context of every question."
  @spec time_fact() :: String.t()
  def time_fact, do: @time

  @doc "The consistency each callback asks for, a constant of this package."
  @spec consistency(atom()) :: Consistency.t()
  def consistency(:scope), do: :minimize_latency
  def consistency(callback) when is_atom(callback), do: :higher_consistency

  @doc "The relation an operation is."
  @spec relation(atom()) :: String.t()
  def relation(operation) when is_atom(operation), do: "can_" <> Atom.to_string(operation)

  @doc "The user a subject is, whatever kind it carries."
  @spec user(Turnstile.subject()) :: String.t()
  def user({_kind, id}), do: "user:#{id}"

  @doc "The object of the store an object is."
  @spec named(Turnstile.object()) :: String.t()
  def named({type, id}), do: "#{type}:#{id}"

  @doc "What the configuration entry names, or an engine error naming what it does not."
  @spec entry(keyword(), atom(), Turnstile.environment()) :: {:ok, entry()} | {:error, Error.t()}
  def entry(options, callback, %{now: _now} = environment) when is_list(options) and is_atom(callback) do
    with {:ok, endpoint} <- fetched(options, :endpoint, callback),
         {:ok, store} <- fetched(options, :store_id, callback) do
      {:ok,
       %{
         callback: callback,
         client: Keyword.get(options, :client, Client.Http),
         endpoint: endpoint,
         store: store,
         model: Keyword.get(options, :model_id),
         context: context(environment)
       }}
    end
  end

  @doc "The answer to one question: one `Check` under the pinned model."
  @spec one(entry(), Turnstile.subject(), atom(), Turnstile.object()) :: {:ok, Answer.t()} | {:error, Error.t()}
  def one(entry, {_kind, _account} = subject, operation, {_type, _id} = object) when is_atom(operation) do
    with {:ok, model} <- pinned(entry),
         request = check(entry, subject, operation, object, model),
         {:ok, allowed?} <- entry.client.check(entry.endpoint, entry.store, request) do
      {:ok, answer(allowed?, operation, model)}
    end
  end

  @doc """
  The rule for an object type: the identifiers `ListObjects` answers with, as
  a `dynamic` over the rows of that type. An answer at the cap or above it
  emits `fallback_event/0` and fails, which is the scope the caller asks per
  page instead.
  """
  @spec scoped(entry(), Turnstile.subject(), atom(), atom()) ::
          {:ok, Turnstile.Adapter.scoped()} | {:error, Error.t()}
  def scoped(entry, {_kind, _account} = subject, operation, type) when is_atom(operation) and is_atom(type) do
    with {:ok, model} <- pinned(entry),
         {:ok, objects} <- listed(entry, subject, operation, type, model),
         {:ok, ids} <- under_cap(objects, operation, type) do
      {:ok, scope(ids, operation, model)}
    end
  end

  @doc "The denial a guard's refusal is for one object, under the entry's model."
  @spec refused(entry()) :: Answer.t()
  def refused(entry) do
    %Answer{
      verdict: :deny,
      reason: :rule_denied,
      version: entry.model,
      meta: %{rule: @guard}
    }
  end

  @doc "The scope a guard's refusal is: the rule no row satisfies, and the denial."
  @spec refused_scope(entry()) :: Turnstile.Adapter.scoped()
  def refused_scope(entry), do: {dynamic([_row], false), refused(entry)}

  defp listed(entry, {_kind, _account} = subject, operation, type, model) do
    request = listing(entry, subject, operation, type, model)

    entry.client.list_objects(entry.endpoint, entry.store, request)
  end

  defp scope(ids, operation, model) do
    {dynamic([row], row.id in ^ids), answer(true, operation, model)}
  end

  defp check(entry, {_kind, _account} = subject, operation, {_type, _id} = object, model) do
    %Check{
      tuple_key: tuple(subject, operation, object),
      model: model,
      context: entry.context,
      consistency: consistency(entry.callback)
    }
  end

  defp listing(entry, {_kind, _account} = subject, operation, type, model) do
    %ListObjects{
      user: user(subject),
      relation: relation(operation),
      type: Atom.to_string(type),
      model: model,
      context: entry.context,
      consistency: consistency(entry.callback)
    }
  end

  defp tuple({_kind, _account} = subject, operation, {_type, _id} = object) do
    %TupleKey{user: user(subject), relation: relation(operation), object: named(object)}
  end

  # At the cap the answer is a page of a longer list, and the server says so
  # by no means other than its length, so a listing this long is no rule.
  defp under_cap(objects, _operation, _type) when length(objects) < @scope_cap do
    {:ok, Enum.map(objects, &identifier/1)}
  end

  defp under_cap(objects, operation, type) do
    count = length(objects)
    detail = "#{count} objects is the cap of one listing, so this scope is limited to a filter per page"
    :telemetry.execute(@fallback, %{count: count}, %{operation: operation, type: type, level: :limited})

    {:error, Client.error(:scope, detail)}
  end

  defp identifier(object) do
    case String.split(object, ":", parts: 2) do
      [_type, id] -> id
      [id] -> id
    end
  end

  # The caller's facts under their own names, and the moment of the call. A
  # date is sent as text, which is what a condition compares timestamps as.
  defp context(%{now: now} = environment) do
    facts = Map.to_list(Map.delete(environment, :now))
    Map.new([{@time, now} | facts], fn {name, value} -> {to_string(name), value(value)} end)
  end

  defp value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp value(%Date{} = value), do: Date.to_iso8601(value)
  defp value(value), do: value

  defp answer(true, operation, model) do
    %Answer{verdict: :allow, reason: :allowed, version: model, meta: %{rule: relation(operation)}}
  end

  defp answer(false, _operation, model) do
    %Answer{verdict: :deny, reason: :deny_by_default, version: model, meta: %{}}
  end

  defp pinned(%{model: nil, callback: callback}) do
    {:error, Client.error(callback, "the configuration entry pins no model, so no question can be asked under one")}
  end

  defp pinned(%{model: model}), do: {:ok, model}

  defp fetched(options, field, callback) do
    case Keyword.fetch(options, field) do
      {:ok, value} -> {:ok, value}
      :error -> {:error, Client.error(callback, "the configuration entry names no #{field}")}
    end
  end
end
