defmodule Turnstile.Port do
  @moduledoc """
  The mechanism behind `Turnstile`'s functions: resolve the configuration,
  build the environment from the caller's map and the clock, ask the
  adapter, fail closed on an engine error or on an exception the decider
  raised, stamp a `Turnstile.Decision`, and publish it.

  Every decision publishes one `[:turnstile, :decision]` event, whose
  metadata is what `docs/events.md` §1 states: who asked and of what kind,
  the operation, the object or the rule a narrowing call answered with, the
  verdict and the reason, the decider and the version of its rules, the
  environment as the caller gave it, what broke where the call failed
  closed, the decision's id, the moment, and the operation id. A decision
  is a read, so it has no transaction. The one measurement is the duration in microseconds, which
  is where a consumer of telemetry looks for it.

  A subject whose kind the port does not know is denied before the adapter
  is asked, and its event says `:unknown`.
  """

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Error
  alias Turnstile.Id

  @options NimbleOptions.new!(
             env: [type: {:map, :atom, :any}, default: %{}, doc: "The environment: facts only the caller knows, by name."],
             operation_id: [type: :string, doc: "The id every record of this operation carries; fresh when absent."]
           )

  @kinds [:user, :non_person_entity, :privileged]
  @event [:turnstile, :decision]

  @typedoc "The options every port function takes."
  @type options :: [env: %{atom() => term()}, operation_id: Id.t()]

  @typedoc "A review's answer per subject: the rule over the object type and the decision it runs under."
  @type reviewed :: %{Turnstile.subject() => {Ecto.Query.dynamic_expr(), Decision.t()}}

  @doc "The three subject kinds the port knows, in the order `docs/design.md` lists them."
  @spec subject_kinds() :: [Turnstile.subject_kind()]
  def subject_kinds, do: @kinds

  @doc "The telemetry event each decision publishes, which is what a consumer attaches to."
  @spec event() :: [atom()]
  def event, do: @event

  @doc "The schema of the options."
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @options

  @doc "Decide for one object; the decision is the record and the value the seam takes."
  @spec authorize(Turnstile.subject(), atom(), Turnstile.object(), options()) ::
          {:ok, Decision.t()} | {:error, Error.t()}
  def authorize({_kind, _account} = subject, operation, {_type, _id} = object, opts)
      when is_atom(operation) and is_list(opts) do
    {decision, answer} = one(subject, operation, object, opts)

    case decision.verdict do
      :allow -> {:ok, decision}
      :deny -> {:error, not_authorized(subject, operation, object, answer)}
    end
  end

  @doc "Decide for one object and answer the verdict alone."
  @spec check(Turnstile.subject(), atom(), Turnstile.object(), options()) :: boolean()
  def check({_kind, _account} = subject, operation, {_type, _id} = object, opts)
      when is_atom(operation) and is_list(opts) do
    {decision, _answer} = one(subject, operation, object, opts)
    decision.verdict == :allow
  end

  @doc """
  The rule a row of the object type must satisfy, with the decision the
  query carries. Under a denied precondition or an unreachable engine the
  rule is one no row satisfies and the verdict is `:deny`.
  """
  @spec scope(Turnstile.subject(), atom(), atom(), options()) :: {Ecto.Query.dynamic_expr(), Decision.t()}
  def scope({_kind, _account} = subject, operation, object_type, opts) when is_atom(operation) and is_atom(object_type) do
    reviewed(prepare(subject, opts), subject, operation, object_type)
  end

  @doc """
  Who can do what: `scope` per subject over an object type, under one
  operation id. Each subject's decision is its own record, so a query the
  reviewer runs under it is logged for that subject; the reviewer's own
  decision over the type is the record of the review.
  """
  @spec review(Turnstile.subject(), [Turnstile.subject()], atom(), atom(), options()) :: reviewed()
  def review({_kind, _account} = reviewer, subjects, operation, object_type, opts)
      when is_list(subjects) and is_atom(operation) and is_atom(object_type) and is_list(opts) do
    call = prepare(reviewer, opts)

    decided(call, reviewer, operation, {object_type, nil}, fn ->
      reviewed = Map.new(subjects, &{&1, reviewed(call, &1, operation, object_type)})
      decision = stamp(call, reviewer, operation, {object_type, nil}, review_answer(), :scoped)
      {reviewed, decision, %{}}
    end)
  end

  defp review_answer, do: %Answer{verdict: :allow, reason: :allowed, meta: %{rule: "review"}}

  # One object: authorize and check share this. The answer travels beside
  # the decision, because a denial names what the record does not carry.
  defp one(subject, operation, {_type, _id} = object, opts) do
    call = prepare(subject, opts)

    decided(call, subject, operation, object, fn ->
      answer = ask(call, subject, operation, object)
      decision = stamp(call, subject, operation, object, answer, answer.verdict)
      {{decision, answer}, decision, said(answer)}
    end)
  end

  # One type for one subject: scope and each subject of a review share
  # this. The event carries the rule in the object's place.
  defp reviewed(call, subject, operation, type) do
    call = %{call | kind: kind(subject)}

    decided(call, subject, operation, {type, nil}, fn ->
      {rule, answer} = scoped(call, subject, operation, type)
      decision = stamp(call, subject, operation, {type, nil}, answer, scope_verdict(answer))
      {{rule, decision}, decision, Map.put(said(answer), :object, rule)}
    end)
  end

  # Everything a call needs, resolved once.
  defp prepare({_kind, _account} = subject, opts) do
    validated = NimbleOptions.validate!(opts, @options)
    config = config!()
    {adapter, options} = Config.adapter(config)

    %{
      config: config,
      adapter: adapter,
      options: options,
      kind: kind(subject),
      env: validated[:env],
      environment: Map.put(validated[:env], :now, config.clock.()),
      operation_id: Keyword.get_lazy(validated, :operation_id, &Id.new/0)
    }
  end

  defp kind({kind, _account}) when kind in @kinds, do: kind
  defp kind({_kind, _account}), do: :unknown

  # The adapter's answer for one object, or the denial the port gives in
  # its place: an unknown subject kind before the adapter is asked, an
  # engine error after.
  defp ask(%{kind: :unknown}, subject, _operation, _object), do: unknown_kind(subject)

  defp ask(call, subject, operation, object) do
    case asked(call, :decide, subject, operation, object) do
      {:ok, %Answer{} = answer} -> answer
      {:error, %Error{reason: :engine_unreachable} = error, exception} -> closed(error, exception)
    end
  end

  # The adapter's answer, or the error the port answers in its place: the
  # engine error the adapter gave, or the exception the adapter raised,
  # which the third element carries so the event names what broke. A
  # decider that raises closes the door rather than reaching the caller, so
  # no decider carries a rescue clause for the driver underneath it.
  defp asked(call, function, subject, operation, object) do
    case answered(call, function, subject, operation, object) do
      {:ok, answer} -> {:ok, answer}
      {:error, %Error{} = error} -> {:error, error, nil}
    end
  rescue
    exception -> {:error, raised(call.adapter, function, exception), exception}
  end

  defp answered(%{adapter: adapter} = call, :decide, subject, operation, object) do
    adapter.decide(subject, operation, object, call.environment, call.options)
  end

  defp answered(%{adapter: adapter} = call, :scope, subject, operation, type) do
    adapter.scope(subject, operation, type, call.environment, call.options)
  end

  defp scoped(%{kind: :unknown}, subject, _operation, _type), do: {refused(), unknown_kind(subject)}

  defp scoped(call, subject, operation, type) do
    case asked(call, :scope, subject, operation, type) do
      {:ok, {rule, %Answer{verdict: :allow} = answer}} -> {rule, answer}
      {:ok, {_rule, %Answer{verdict: :deny} = answer}} -> {refused(), answer}
      {:error, %Error{reason: :engine_unreachable} = error, exception} -> {refused(), closed(error, exception)}
    end
  end

  defp refused, do: dynamic([_row], false)

  defp scope_verdict(%Answer{verdict: :allow}), do: :scoped
  defp scope_verdict(%Answer{verdict: :deny}), do: :deny

  # The door closed: the answer carries what broke, which is the exception
  # the decider raised, or the error it answered with when it raised none.
  defp closed(%Error{reason: :engine_unreachable, detail: detail} = error, nil) do
    %Answer{verdict: :deny, reason: :engine_unreachable, meta: %{detail: detail, exception: error}}
  end

  defp closed(%Error{reason: :engine_unreachable, detail: detail}, exception) do
    %Answer{verdict: :deny, reason: :engine_unreachable, meta: %{detail: detail, exception: exception}}
  end

  defp raised(adapter, function, exception) do
    %Error{
      reason: :engine_unreachable,
      detail: "#{inspect(adapter)} raised during #{function}: #{Exception.message(exception)}"
    }
  end

  # What the event says beyond the verdict: what broke, where the answer
  # closed the door in the decider's place.
  defp said(%Answer{meta: %{exception: exception}}), do: %{exception: exception}
  defp said(%Answer{}), do: %{}

  defp unknown_kind({kind, _account}) do
    %Answer{verdict: :deny, reason: :unknown_subject_kind, meta: %{kind: kind}}
  end

  defp stamp(call, subject, operation, object, %Answer{} = answer, verdict) do
    %Decision{
      id: Id.new(),
      subject: subject,
      object: object,
      operation: operation,
      verdict: verdict,
      reason: answer.reason,
      adapter: call.adapter,
      policy_version: answer.version,
      operation_id: call.operation_id,
      at: call.environment.now
    }
  end

  # One decision, published after the call. `fun` returns the call's
  # result, the decision, and what the call knows only afterwards, which
  # for a narrowing call is the rule in the object's place.
  defp decided(call, subject, operation, object, fun) do
    started = System.monotonic_time()

    try do
      {result, decision, extra} = fun.()
      publish(call, subject, operation, object, started, Map.merge(extra, verdict_out(decision)))
      result
    rescue
      exception ->
        publish(call, subject, operation, object, started, %{exception: exception})
        reraise exception, __STACKTRACE__
    end
  end

  defp publish(call, subject, operation, object, started, said) do
    duration = System.convert_time_unit(System.monotonic_time() - started, :native, :microsecond)

    metadata =
      Map.merge(
        %{
          subject: subject,
          subject_kind: call.kind,
          operation: operation,
          object: object,
          verdict: nil,
          reason: nil,
          decider: call.adapter,
          version: nil,
          env: call.env,
          exception: nil,
          decision_id: nil,
          time: call.environment.now,
          operation_id: call.operation_id
        },
        said
      )

    :telemetry.execute(@event, %{duration: duration}, metadata)
  end

  defp verdict_out(%Decision{} = decision) do
    %{verdict: decision.verdict, reason: decision.reason, version: decision.policy_version, decision_id: decision.id}
  end

  defp not_authorized(subject, operation, object, %Answer{} = answer) do
    Error.denied(subject, operation, object, answer.reason, Map.get(answer.meta, :detail))
  end

  defp config! do
    case Config.resolve() do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end
end
