defmodule Turnstile.Fga.Decide do
  @moduledoc """
  The answers the adapter gives: an operation becomes a relation, a subject
  and an object become the two ends of a tuple, and the server answers
  whether a path joins them.

  An operation is the relation `can_` and its name, which is the one
  translation this package makes, and a subject is a user of the store
  whatever kind it carries, because a graph compares by walking rather than
  by equality. An allowance names that relation as the rule that allowed. A
  denial is denied by default: a graph has no rule that denies, it has no
  path, and saying a rule denied would name something that does not exist.

  The environment is the context every call carries, which is what a
  condition on a tuple is evaluated against: the caller's facts under their
  own names, and the moment of the call under `current_time`, the one name
  this package reserves. A condition that compares a date on a tuple with
  the present therefore needs nothing of the caller.

  An entry is where the question goes and what it is asked under: the client,
  the endpoint, the store, the model, that context, and the position the
  store has been drained to. Every answer carries the model as its policy
  version and that position as its applied position, which is the state the
  engine could have seen. The consistency of each call is a constant of this
  package: a decision asks for the higher consistency, so a tuple the
  projector has written is not missed, and a listing asks for the lower one,
  since a scope is a filter over rows the caller reads anyway.

  A batch is one call per fifty questions, the pinned server's own limit,
  which is lower than the cap on identifiers a rule may carry. A scope is
  one `ListObjects`: under the cap its identifiers become the rule, and at
  the cap or above it the answer is short of the truth without saying so, so
  this module emits `fallback_event/0` with the level `limited` and fails,
  and the caller asks per page instead.

  A guard is a rule outside the graph. Where the binding names one and it
  does not admit the operation, this module answers the denial and asks
  nothing, and that denial names the guard as the rule that denied, because
  something denied it rather than nothing allowing it.

  An operation the model has no relation for is a question the server
  refuses, and that refusal is answered as it stands rather than turned into
  a denial of this module's own, because nothing here can tell an operation
  no one declared from a model that was published wrong. Either way the
  caller denies.
  """

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Fga.Client
  alias Turnstile.Fga.Client.BatchCheck
  alias Turnstile.Fga.Client.Check
  alias Turnstile.Fga.Client.Expand
  alias Turnstile.Fga.Client.ListObjects
  alias Turnstile.Fga.Client.Tree
  alias Turnstile.Fga.Consistency
  alias Turnstile.Fga.TupleKey
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject

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
          context: map(),
          applied: non_neg_integer() | nil
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
  @spec user(Subject.t()) :: String.t()
  def user(%Subject{} = subject) do
    {:user, id} = Subject.ref(subject)

    "user:#{id}"
  end

  @doc "The object of the store an object is."
  @spec named(Object.t()) :: String.t()
  def named(%Object{type: type, id: id}), do: "#{type}:#{id}"

  @doc "What the configuration entry names, or an engine error naming what it does not."
  @spec entry(keyword(), atom(), Environment.t()) :: {:ok, entry()} | {:error, Error.Engine.t()}
  def entry(options, callback, %Environment{} = environment) when is_list(options) and is_atom(callback) do
    with {:ok, endpoint} <- fetched(options, :endpoint, callback),
         {:ok, store} <- fetched(options, :store_id, callback) do
      {:ok,
       %{
         callback: callback,
         client: Keyword.get(options, :client, Client.Http),
         endpoint: endpoint,
         store: store,
         model: Keyword.get(options, :model_id),
         context: context(environment),
         applied: nil
       }}
    end
  end

  @doc "The entry with the position the store has been drained to, which every answer carries."
  @spec applied(entry(), non_neg_integer() | nil) :: entry()
  def applied(entry, position) when is_nil(position) or is_integer(position), do: %{entry | applied: position}

  @doc "The answer to one question: one `Check` under the pinned model."
  @spec one(entry(), Subject.t(), atom(), Object.t()) :: {:ok, Answer.t()} | {:error, Error.Engine.t()}
  def one(entry, %Subject{} = subject, operation, %Object{} = object) when is_atom(operation) do
    with {:ok, model} <- pinned(entry),
         request = check(entry, subject, operation, object, model),
         {:ok, allowed?} <- entry.client.check(entry.endpoint, entry.store, request) do
      {:ok, answer(allowed?, operation, model, entry.applied)}
    end
  end

  @doc "The answers for a list of objects, one per object reference, in calls of at most fifty questions."
  @spec many(entry(), Subject.t(), atom(), [Object.t()]) ::
          {:ok, %{Object.ref() => Answer.t()}} | {:error, Error.Engine.t()}
  def many(entry, %Subject{} = subject, operation, objects) when is_atom(operation) and is_list(objects) do
    with {:ok, model} <- pinned(entry),
         {:ok, allowed} <- asked(entry, keyed(subject, operation, objects), model) do
      {:ok, Map.new(objects, &{Object.ref(&1), answer(named(&1) in allowed, operation, model, entry.applied)})}
    end
  end

  @doc """
  The rule for an object type: the identifiers `ListObjects` answers with, as
  a `dynamic` over the rows of that type. An answer at the cap or above it
  emits `fallback_event/0` and fails, which is the scope the caller asks per
  page instead.
  """
  @spec scoped(entry(), Subject.t(), atom(), atom()) :: {:ok, Scope.t()} | {:error, Error.Engine.t()}
  def scoped(entry, %Subject{} = subject, operation, type) when is_atom(operation) and is_atom(type) do
    with {:ok, model} <- pinned(entry),
         {:ok, objects} <- listed(entry, subject, operation, type, model),
         {:ok, ids} <- under_cap(objects, operation, type) do
      {:ok, scope(ids, operation, model, entry.applied)}
    end
  end

  @doc "The denial a guard's refusal is for one object, under the entry's model and position."
  @spec refused(entry()) :: Answer.t()
  def refused(entry) do
    %Answer{
      verdict: :deny,
      reason: Reason.rule_denied(@guard),
      policy_version: entry.model,
      applied_position: entry.applied
    }
  end

  @doc "The denial a guard's refusal is for every object of a batch."
  @spec refused_all(entry(), [Object.t()]) :: %{Object.ref() => Answer.t()}
  def refused_all(entry, objects) when is_list(objects) do
    Map.new(objects, &{Object.ref(&1), refused(entry)})
  end

  @doc "The scope a guard's refusal is: the rule no row satisfies, and the denial."
  @spec refused_scope(entry()) :: Scope.t()
  def refused_scope(entry), do: %Scope{rule: dynamic([_row], false), answer: refused(entry)}

  @doc "The explanation a guard's refusal is: the denial, and no relation that holds."
  @spec refused_explanation(entry()) :: Explanation.t()
  def refused_explanation(entry), do: %Explanation{answer: refused(entry), matched: []}

  @doc """
  The explanation for one object: the answer, and where it is allowed the
  relations the operation is computed from that hold. The tree comes from one
  `Expand` and which of its branches hold from one `BatchCheck`, so an
  explanation is three calls and no walk of this module's own.
  """
  @spec explained(entry(), Subject.t(), atom(), Object.t()) :: {:ok, Explanation.t()} | {:error, Error.Engine.t()}
  def explained(entry, %Subject{} = subject, operation, %Object{} = object) when is_atom(operation) do
    with {:ok, %Answer{} = answer} <- one(entry, subject, operation, object) do
      matched(entry, subject, operation, object, answer)
    end
  end

  defp listed(entry, %Subject{} = subject, operation, type, model) do
    request = listing(entry, subject, operation, type, model)

    entry.client.list_objects(entry.endpoint, entry.store, request)
  end

  defp scope(ids, operation, model, applied) do
    %Scope{rule: dynamic([row], row.id in ^ids), answer: answer(true, operation, model, applied)}
  end

  defp matched(_entry, _subject, _operation, _object, %Answer{verdict: :deny} = answer) do
    {:ok, %Explanation{answer: answer, matched: []}}
  end

  defp matched(entry, subject, operation, object, %Answer{} = answer) do
    request = %Expand{relation: relation(operation), object: named(object), model: answer.policy_version}

    with {:ok, %Tree{} = tree} <- entry.client.expand(entry.endpoint, entry.store, request),
         {:ok, holding} <- asked(entry, branches(subject, tree), answer.policy_version) do
      {:ok, %Explanation{answer: answer, matched: Enum.sort(holding)}}
    end
  end

  # Each branch of the tree as a question of its own: whether the subject
  # holds that relation on that object. A branch names the relation it is
  # computed from, on this object or on another, and that name is what an
  # explanation reports.
  defp branches(%Subject{} = subject, %Tree{} = tree) do
    for %Tree{object: object, relation: relation} <- tree.children do
      {"#{object}##{relation}", %TupleKey{user: user(subject), relation: relation, object: object}}
    end
  end

  # Questions under names of the caller's own, in calls of at most the limit
  # of one call, answering the names that hold.
  defp asked(entry, questions, model) do
    step = fn chunk, {:ok, holding} -> chunked(entry, chunk, model, holding) end

    questions
    |> Enum.chunk_every(Client.max_checks_per_batch())
    |> Enum.reduce_while({:ok, []}, step)
  end

  # The identifier of a question is the server's to accept and takes letters,
  # digits, and dashes alone, so a question is asked under its place in the
  # call and answered under the name the caller gave it.
  defp chunked(entry, questions, model, holding) do
    numbered = Enum.with_index(questions)

    request = %BatchCheck{
      checks: checks(numbered),
      model: model,
      context: entry.context,
      consistency: consistency(entry.callback)
    }

    case entry.client.batch_check(entry.endpoint, entry.store, request) do
      {:ok, answered} -> {:cont, {:ok, holding ++ held(numbered, answered)}}
      {:error, %Error.Engine{} = error} -> {:halt, {:error, error}}
    end
  end

  defp checks(numbered), do: for({{_name, tuple}, index} <- numbered, do: {"c-#{index}", tuple})

  defp held(numbered, answered) do
    for {{name, _tuple}, index} <- numbered, Map.get(answered, "c-#{index}") == true, do: name
  end

  defp keyed(%Subject{} = subject, operation, objects) do
    for object <- objects, do: {named(object), tuple(subject, operation, object)}
  end

  defp check(entry, %Subject{} = subject, operation, %Object{} = object, model) do
    %Check{
      tuple_key: tuple(subject, operation, object),
      model: model,
      context: entry.context,
      consistency: consistency(entry.callback)
    }
  end

  defp listing(entry, %Subject{} = subject, operation, type, model) do
    %ListObjects{
      user: user(subject),
      relation: relation(operation),
      type: Atom.to_string(type),
      model: model,
      context: entry.context,
      consistency: consistency(entry.callback)
    }
  end

  defp tuple(%Subject{} = subject, operation, %Object{} = object) do
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
  defp context(%Environment{now: now, facts: facts}) do
    Map.new([{@time, now} | Map.to_list(facts)], fn {name, value} -> {to_string(name), value(value)} end)
  end

  defp value(%DateTime{} = value), do: DateTime.to_iso8601(value)
  defp value(%NaiveDateTime{} = value), do: NaiveDateTime.to_iso8601(value)
  defp value(%Date{} = value), do: Date.to_iso8601(value)
  defp value(value), do: value

  defp answer(true, operation, model, applied) do
    %Answer{
      verdict: :allow,
      reason: Reason.allowed(relation(operation)),
      policy_version: model,
      applied_position: applied
    }
  end

  defp answer(false, _operation, model, applied) do
    %Answer{verdict: :deny, reason: Reason.deny_by_default(), policy_version: model, applied_position: applied}
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
