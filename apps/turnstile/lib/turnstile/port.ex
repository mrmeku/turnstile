defmodule Turnstile.Port do
  @moduledoc """
  The mechanism behind `Turnstile`'s functions: resolve the configuration,
  build the environment from the caller's map and the clock, ask the
  adapter, fail closed on an engine error or on an exception the decider
  raised, stamp a `Turnstile.Decision`, and publish it.

  Every call publishes one `[:turnstile, :decision]` event, whose metadata
  is what `docs/events.md` §1 states: who asked and of what kind, the
  operation, the object or the rule a narrowing call answered with, the
  verdict and the reason, the decider and the version of its rules, the
  environment as the caller gave it, the exception where the call raised,
  the moment, and the operation id. A decision is a read, so it has no
  transaction. The one measurement is the duration in microseconds, which
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

  @typedoc "A batch's verdicts, one per object reference."
  @type verdicts :: %{Turnstile.object() => Answer.verdict()}

  @typedoc "A review's answer per subject: the rule over an object type, or the allowed references of a population."
  @type reviewed :: %{Turnstile.subject() => Ecto.Query.dynamic_expr() | [Turnstile.object()]}

  @doc "The three subject kinds the port knows, in the order the reference lists them."
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
    {decision, answer} = one(:authorize, subject, operation, object, opts)

    case decision.verdict do
      :allow -> {:ok, decision}
      :deny -> {:error, not_authorized(subject, operation, object, answer)}
    end
  end

  @doc "Decide for one object and answer the verdict alone."
  @spec check(Turnstile.subject(), atom(), Turnstile.object(), options()) :: boolean()
  def check({_kind, _account} = subject, operation, {_type, _id} = object, opts)
      when is_atom(operation) and is_list(opts) do
    {decision, _answer} = one(:check, subject, operation, object, opts)
    decision.verdict == :allow
  end

  @doc "Decide for many objects of one type; one record for all of them."
  @spec batch(Turnstile.subject(), atom(), [Turnstile.object()], options()) :: verdicts()
  def batch({_kind, _account} = subject, operation, objects, opts) when is_atom(operation) and is_list(objects) do
    {verdicts, _decision} = many(:batch, subject, operation, objects, opts)
    verdicts
  end

  @doc "The objects among `objects` the subject may perform the operation on, in the order given."
  @spec filter(Turnstile.subject(), atom(), [Turnstile.object()], options()) :: [Turnstile.object()]
  def filter({_kind, _account} = subject, operation, objects, opts) when is_atom(operation) and is_list(objects) do
    {verdicts, _decision} = many(:filter, subject, operation, objects, opts)
    Enum.filter(objects, &(Map.fetch!(verdicts, &1) == :allow))
  end

  @doc """
  The rule a row of the object type must satisfy, with the decision the
  query carries. Under a denied precondition or an unreachable engine the
  rule is one no row satisfies and the verdict is `:deny`.
  """
  @spec scope(Turnstile.subject(), atom(), atom(), options()) :: {Ecto.Query.dynamic_expr(), Decision.t()}
  def scope({_kind, _account} = subject, operation, object_type, opts) when is_atom(operation) and is_atom(object_type) do
    call = prepare(subject, opts)

    decided(call, subject, operation, {object_type, nil}, fn ->
      {rule, answer} = scoped(call, subject, operation, object_type)
      decision = stamp(call, subject, operation, {object_type, nil}, answer, scope_verdict(answer))
      {{rule, decision}, decision, Map.put(said(answer), :object, rule)}
    end)
  end

  @doc "The answer with what produced it on `meta`, where the adapter can say; unsupported otherwise."
  @spec explain(Turnstile.subject(), atom(), Turnstile.object(), options()) ::
          {:ok, Answer.t(), Decision.t()} | {:error, Error.t()}
  def explain({_kind, _account} = subject, operation, {_type, _id} = object, opts)
      when is_atom(operation) and is_list(opts) do
    call = prepare(subject, opts)

    if function_exported?(call.adapter, :explain, 5) do
      explained(call, subject, operation, object)
    else
      {:error, unsupported(call.adapter, "explain/5, which it does not define")}
    end
  end

  @doc """
  Who can do what: `scope` per subject over an object type, or `batch` per
  subject over a population of objects, under one record for the reviewer.
  """
  @spec review(Turnstile.subject(), [Turnstile.subject()], atom(), atom() | [Turnstile.object()], options()) :: reviewed()
  def review({_kind, _account} = reviewer, subjects, operation, population, opts)
      when is_list(subjects) and is_atom(operation) and is_list(opts) do
    call = prepare(reviewer, opts)
    type = population_type(population)

    decided(call, reviewer, operation, {type, nil}, fn ->
      reviewed = Map.new(subjects, &{&1, reviewed(call, &1, operation, population)})
      decision = stamp(call, reviewer, operation, {type, nil}, review_answer(), :scoped)
      {reviewed, decision, %{}}
    end)
  end

  defp review_answer, do: %Answer{verdict: :allow, reason: :allowed, meta: %{rule: "review"}}

  # One object: authorize and check share this. The answer travels beside
  # the decision, because a denial names what the record does not carry.
  defp one(function, subject, operation, {_type, _id} = object, opts) do
    call = prepare(subject, opts)

    decided(call, subject, operation, object, fn ->
      answer = ask(call, function, subject, operation, object)
      decision = stamp(call, subject, operation, object, answer, answer.verdict)
      {{decision, answer}, decision, said(answer)}
    end)
  end

  # Many objects: batch and filter share this.
  defp many(function, subject, operation, objects, opts) do
    call = prepare(subject, opts)
    type = population_type(objects)

    decided(call, subject, operation, {type, nil}, fn ->
      {verdicts, closed} = verdicts(call, function, subject, operation, objects)
      answer = closed || summary(verdicts)
      decision = stamp(call, subject, operation, {type, nil}, answer, answer.verdict)
      {{verdicts, decision}, decision, said(answer)}
    end)
  end

  defp explained(call, subject, operation, {_type, _id} = object) do
    decided(call, subject, operation, object, fn ->
      case asked(call, :explain, subject, operation, object) do
        {:ok, %Answer{} = answer} ->
          decision = stamp(call, subject, operation, object, answer, answer.verdict)
          {{:ok, answer, decision}, decision, %{}}

        {:error, %Error{reason: :unsupported} = error, _exception} ->
          {{:error, error}, nil, %{}}

        {:error, %Error{reason: :engine_unreachable} = error, exception} ->
          answer = closed(error, exception)
          decision = stamp(call, subject, operation, object, answer, :deny)
          {{:ok, answer, decision}, decision, said(answer)}
      end
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
  defp ask(%{kind: :unknown}, _function, subject, _operation, _object), do: unknown_kind(subject)

  defp ask(call, function, subject, operation, object) do
    case asked(call, function, subject, operation, object) do
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

  defp answered(%{adapter: adapter} = call, :authorize, subject, operation, object) do
    adapter.authorize(subject, operation, object, call.environment, call.options)
  end

  defp answered(%{adapter: adapter} = call, :check, subject, operation, object) do
    adapter.check(subject, operation, object, call.environment, call.options)
  end

  defp answered(%{adapter: adapter} = call, :batch, subject, operation, objects) do
    adapter.batch(subject, operation, objects, call.environment, call.options)
  end

  defp answered(%{adapter: adapter} = call, :scope, subject, operation, type) do
    adapter.scope(subject, operation, type, call.environment, call.options)
  end

  defp answered(%{adapter: adapter} = call, :explain, subject, operation, object) do
    adapter.explain(subject, operation, object, call.environment, call.options)
  end

  # The verdict per object, beside the denial the port gave in their place
  # where it gave one, so a batch records the same reason one object would.
  defp verdicts(%{kind: :unknown}, _function, subject, _operation, objects) do
    answer = unknown_kind(subject)
    {Map.new(objects, &{&1, answer.verdict}), answer}
  end

  defp verdicts(call, _function, subject, operation, objects) do
    case asked(call, :batch, subject, operation, objects) do
      {:ok, answers} ->
        {Map.new(objects, &{&1, Map.fetch!(answers, &1).verdict}), nil}

      {:error, %Error{reason: :engine_unreachable} = error, exception} ->
        {Map.new(objects, &{&1, :deny}), closed(error, exception)}
    end
  end

  defp scoped(%{kind: :unknown}, subject, _operation, _type), do: {refused(), unknown_kind(subject)}

  defp scoped(call, subject, operation, type) do
    case asked(call, :scope, subject, operation, type) do
      {:ok, {rule, %Answer{verdict: :allow} = answer}} -> {rule, answer}
      {:ok, {_rule, %Answer{verdict: :deny} = answer}} -> {refused(), answer}
      {:error, %Error{reason: :engine_unreachable} = error, exception} -> {refused(), closed(error, exception)}
    end
  end

  defp reviewed(call, subject, operation, type) when is_atom(type) do
    {rule, _answer} = scoped(%{call | kind: kind(subject)}, subject, operation, type)
    rule
  end

  defp reviewed(call, subject, operation, objects) when is_list(objects) do
    {verdicts, _closed} = verdicts(%{call | kind: kind(subject)}, :batch, subject, operation, objects)

    verdicts
    |> Enum.filter(fn {_object, verdict} -> verdict == :allow end)
    |> Enum.map(fn {object, _verdict} -> object end)
    |> Enum.sort()
  end

  defp refused, do: dynamic([_row], false)

  defp scope_verdict(%Answer{verdict: :allow}), do: :scoped
  defp scope_verdict(%Answer{verdict: :deny}), do: :deny

  defp unsupported(adapter, feature) do
    %Error{reason: :unsupported, detail: "#{inspect(adapter)} does not support #{feature}"}
  end

  defp closed(%Error{reason: :engine_unreachable, detail: detail}, nil) do
    %Answer{verdict: :deny, reason: :engine_unreachable, meta: %{detail: detail}}
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

  # What the event says beyond the verdict: the exception, where a decider
  # raised and the answer closed the door in its place.
  defp said(%Answer{meta: %{exception: exception}}), do: %{exception: exception}
  defp said(%Answer{}), do: %{}

  defp unknown_kind({kind, _account}) do
    %Answer{verdict: :deny, reason: :unknown_subject_kind, meta: %{kind: kind}}
  end

  # A batch's one answer: allowed when every object is, denied otherwise.
  defp summary(verdicts) do
    if map_size(verdicts) > 0 and Enum.all?(verdicts, fn {_object, verdict} -> verdict == :allow end) do
      %Answer{verdict: :allow, reason: :allowed, meta: %{rule: "batch"}}
    else
      %Answer{verdict: :deny, reason: :deny_by_default}
    end
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
  # result, the decision or nil where the adapter answered none, and what
  # the call knows only afterwards, which for a narrowing call is the rule
  # in the object's place.
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
          time: call.environment.now,
          operation_id: call.operation_id
        },
        said
      )

    :telemetry.execute(@event, %{duration: duration}, metadata)
  end

  defp verdict_out(nil), do: %{}

  defp verdict_out(%Decision{} = decision) do
    %{verdict: decision.verdict, reason: decision.reason, version: decision.policy_version}
  end

  defp population_type([{type, _id} | _rest]), do: type
  defp population_type(type) when is_atom(type), do: type
  defp population_type([]), do: nil

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
