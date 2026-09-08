defmodule Turnstile.Port do
  @moduledoc """
  The mechanism behind `Turnstile`'s functions: resolve the configuration,
  build the environment from the clock and the caller's facts, read the
  ledger head, ask the adapter, fail closed on an engine error, stamp a
  `Turnstile.Decision`, and emit it as a telemetry span.

  Every call is one span. Its name is `[:turnstile, kind]` where `kind` is
  the subject's, `:user`, `:non_person_entity`, or `:privileged`, and
  `:unknown` for any other, which is denied before the adapter is asked.
  The `:start` event is the attempt: subject, operation, object or type,
  `operation_id`, and the head position. The `:stop` event carries the
  decision as `Turnstile.Decision.to_map/1` under `decision`, and for
  `batch` and `filter` the verdicts per object and the ids, listed up to
  `caps[:batch_ids]` and beyond that a count and a SHA-256 of the sorted
  ids; for `scope` the rule inspected, truncated at `caps[:rule_bytes]`
  with a hash of the full text. The `:exception` event is the failure.
  """

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Config
  alias Turnstile.Decision
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Id
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject

  @options NimbleOptions.new!(
             facts: [type: {:map, :atom, :any}, default: %{}, doc: "Facts only the caller knows, by name."],
             operation_id: [type: :string, doc: "The id every record of this operation carries; fresh when absent."]
           )

  @kinds [:user, :non_person_entity, :privileged]
  @spans [:user, :non_person_entity, :privileged, :unknown]

  @typedoc "The options every port function takes."
  @type options :: [facts: %{atom() => term()}, operation_id: Id.t()]

  @typedoc "A batch's verdicts, one per object reference."
  @type verdicts :: %{Object.ref() => Answer.verdict()}

  @typedoc "A review's answer per subject: the rule over an object type, or the allowed references of a population."
  @type reviewed :: %{Subject.t() => Ecto.Query.dynamic_expr() | [Object.ref()]}

  @doc "The span names the port emits, with their three suffixes."
  @spec events() :: [[atom()]]
  def events do
    for kind <- @spans, suffix <- [:start, :stop, :exception], do: [:turnstile, kind, suffix]
  end

  @doc "The schema of the options."
  @spec options_schema() :: NimbleOptions.t()
  def options_schema, do: @options

  @doc "Decide for one object; the decision is the record and the value the seam takes."
  @spec authorize(Subject.t(), atom(), Object.t(), options()) :: {:ok, Decision.t()} | {:error, Error.NotAuthorized.t()}
  def authorize(%Subject{} = subject, operation, %Object{} = object, opts) when is_atom(operation) and is_list(opts) do
    decision = one(:authorize, subject, operation, object, opts)

    case decision.verdict do
      :allow -> {:ok, decision}
      :deny -> {:error, not_authorized(subject, operation, Object.ref(object), decision.reason)}
    end
  end

  @doc "Decide for one object and answer the verdict alone."
  @spec check(Subject.t(), atom(), Object.t(), options()) :: boolean()
  def check(%Subject{} = subject, operation, %Object{} = object, opts) when is_atom(operation) and is_list(opts) do
    one(:check, subject, operation, object, opts).verdict == :allow
  end

  @doc "Decide for many objects of one type; one record for all of them."
  @spec batch(Subject.t(), atom(), [Object.t()], options()) :: verdicts()
  def batch(%Subject{} = subject, operation, objects, opts) when is_atom(operation) and is_list(objects) do
    {verdicts, _decision} = many(:batch, subject, operation, objects, opts)
    verdicts
  end

  @doc "The objects among `objects` the subject may perform the operation on, in the order given."
  @spec filter(Subject.t(), atom(), [Object.t()], options()) :: [Object.t()]
  def filter(%Subject{} = subject, operation, objects, opts) when is_atom(operation) and is_list(objects) do
    {verdicts, _decision} = many(:filter, subject, operation, objects, opts)
    Enum.filter(objects, &(Map.fetch!(verdicts, Object.ref(&1)) == :allow))
  end

  @doc """
  The rule a row of the object type must satisfy, with the decision the
  query carries. Under a denied precondition or an unreachable engine the
  rule is one no row satisfies and the verdict is `:deny`.
  """
  @spec scope(Subject.t(), atom(), atom(), options()) :: {Ecto.Query.dynamic_expr(), Decision.t()}
  def scope(%Subject{} = subject, operation, object_type, opts) when is_atom(operation) and is_atom(object_type) do
    call = prepare(subject, opts)

    span(call, subject, operation, {object_type, nil}, fn ->
      {rule, answer} = scoped(call, subject, operation, object_type)
      decision = stamp(call, subject, operation, {object_type, nil}, answer, scope_verdict(answer))
      {{rule, decision}, decision, %{rule: rule_text(rule, call.config)}}
    end)
  end

  @doc "The answer with what produced it, where the adapter can say; unsupported otherwise."
  @spec explain(Subject.t(), atom(), Object.t(), options()) ::
          {:ok, Explanation.t(), Decision.t()} | {:error, Error.Unsupported.t()}
  def explain(%Subject{} = subject, operation, %Object{} = object, opts) when is_atom(operation) and is_list(opts) do
    call = prepare(subject, opts)

    if function_exported?(call.adapter, :explain, 5) do
      explained(call, subject, operation, object)
    else
      {:error,
       %Error.Unsupported{adapter: call.adapter, feature: :explain, note: "the adapter does not define explain/5"}}
    end
  end

  @doc """
  Who can do what: `scope` per subject over an object type, or `batch` per
  subject over a population of objects, under one record for the reviewer.
  """
  @spec review(Subject.t(), [Subject.t()], atom(), atom() | [Object.t()], options()) :: reviewed()
  def review(%Subject{} = reviewer, subjects, operation, population, opts)
      when is_list(subjects) and is_atom(operation) and is_list(opts) do
    call = prepare(reviewer, opts)
    type = population_type(population)

    span(call, reviewer, operation, {type, nil}, fn ->
      reviewed = Map.new(subjects, &{&1, reviewed(call, &1, operation, population)})
      decision = stamp(call, reviewer, operation, {type, nil}, review_answer(), :scoped)
      {reviewed, decision, %{reviewed: review_out(reviewed)}}
    end)
  end

  defp review_answer do
    %Answer{verdict: :allow, reason: Reason.allowed("review"), policy_version: nil, applied_position: nil}
  end

  defp review_out(reviewed) when is_map(reviewed) do
    Map.new(reviewed, fn {subject, value} -> {Subject.ref(subject), review_value_out(value)} end)
  end

  # One object: authorize and check share this.
  defp one(function, subject, operation, %Object{} = object, opts) do
    call = prepare(subject, opts)
    ref = Object.ref(object)

    span(call, subject, operation, ref, fn ->
      answer = ask(call, function, subject, operation, object)
      decision = stamp(call, subject, operation, ref, answer, answer.verdict)
      {decision, decision, %{}}
    end)
  end

  # Many objects: batch and filter share this.
  defp many(function, subject, operation, objects, opts) do
    call = prepare(subject, opts)
    type = population_type(objects)

    span(call, subject, operation, {type, nil}, fn ->
      verdicts = verdicts(call, function, subject, operation, objects)
      answer = summary(verdicts)
      decision = stamp(call, subject, operation, {type, nil}, answer, answer.verdict)
      {{verdicts, decision}, decision, %{verdicts: verdicts, ids: ids(Map.keys(verdicts), call.config)}}
    end)
  end

  defp explained(call, subject, operation, %Object{} = object) do
    ref = Object.ref(object)

    span(call, subject, operation, ref, fn ->
      case asked(call, :explain, subject, operation, object) do
        {:ok, %Explanation{answer: answer} = explanation} ->
          decision = stamp(call, subject, operation, ref, answer, answer.verdict)
          {{:ok, explanation, decision}, decision, %{}}

        {:error, %Error.Unsupported{} = error} ->
          {{:error, error}, nil, %{}}

        {:error, %Error.Engine{} = error} ->
          answer = closed(error)
          decision = stamp(call, subject, operation, ref, answer, :deny)
          {{:ok, %Explanation{answer: answer, matched: []}, decision}, decision, %{}}
      end
    end)
  end

  # Everything a call needs, resolved once.
  defp prepare(%Subject{} = subject, opts) do
    validated = NimbleOptions.validate!(opts, @options)
    config = config!()
    {adapter, options} = Config.adapter(config)

    %{
      config: config,
      adapter: adapter,
      options: options,
      kind: kind(subject),
      environment: %Environment{now: config.clock.now(), facts: validated[:facts]},
      operation_id: Keyword.get_lazy(validated, :operation_id, &Id.new/0),
      head: head(config)
    }
  end

  defp kind(%Subject{kind: kind}) when kind in @kinds, do: kind
  defp kind(%Subject{}), do: :unknown

  defp head(%Config{ledger: :none}), do: {:ok, nil}
  defp head(%Config{ledger: {ledger, options}}), do: ledger.head(options)

  # The adapter's answer for one object, or the denial the port gives in
  # its place: an unknown subject kind before the adapter is asked, an
  # engine error after.
  defp ask(%{kind: :unknown}, _function, subject, _operation, _object), do: unknown_kind(subject)

  defp ask(call, function, subject, operation, object) do
    case asked(call, function, subject, operation, object) do
      {:ok, %Answer{} = answer} -> answer
      {:error, %Error.Engine{} = error} -> closed(error)
    end
  end

  defp asked(%{head: {:error, %Error.Engine{} = error}}, _function, _subject, _operation, _object), do: {:error, error}

  defp asked(%{adapter: adapter} = call, :authorize, subject, operation, object) do
    adapter.authorize(subject, operation, object, call.environment, call.options)
  end

  defp asked(%{adapter: adapter} = call, :check, subject, operation, object) do
    adapter.check(subject, operation, object, call.environment, call.options)
  end

  defp asked(%{adapter: adapter} = call, :batch, subject, operation, objects) do
    adapter.batch(subject, operation, objects, call.environment, call.options)
  end

  defp asked(%{adapter: adapter} = call, :scope, subject, operation, type) do
    adapter.scope(subject, operation, type, call.environment, call.options)
  end

  defp asked(%{adapter: adapter} = call, :explain, subject, operation, object) do
    adapter.explain(subject, operation, object, call.environment, call.options)
  end

  defp verdicts(%{kind: :unknown}, _function, subject, _operation, objects) do
    verdict = unknown_kind(subject).verdict
    Map.new(objects, &{Object.ref(&1), verdict})
  end

  defp verdicts(call, _function, subject, operation, objects) do
    case asked(call, :batch, subject, operation, objects) do
      {:ok, answers} -> Map.new(objects, &{Object.ref(&1), Map.fetch!(answers, Object.ref(&1)).verdict})
      {:error, %Error.Engine{}} -> Map.new(objects, &{Object.ref(&1), :deny})
    end
  end

  defp scoped(%{kind: :unknown}, subject, _operation, _type), do: {refused(), unknown_kind(subject)}

  defp scoped(call, subject, operation, type) do
    case asked(call, :scope, subject, operation, type) do
      {:ok, %Scope{rule: rule, answer: %Answer{verdict: :allow} = answer}} -> {rule, answer}
      {:ok, %Scope{answer: %Answer{verdict: :deny} = answer}} -> {refused(), answer}
      {:error, %Error.Engine{} = error} -> {refused(), closed(error)}
    end
  end

  defp reviewed(call, subject, operation, type) when is_atom(type) do
    {rule, _answer} = scoped(%{call | kind: kind(subject)}, subject, operation, type)
    rule
  end

  defp reviewed(call, subject, operation, objects) when is_list(objects) do
    %{call | kind: kind(subject)}
    |> verdicts(:batch, subject, operation, objects)
    |> Enum.filter(fn {_ref, verdict} -> verdict == :allow end)
    |> Enum.map(fn {ref, _verdict} -> ref end)
    |> Enum.sort()
  end

  defp refused, do: dynamic([_row], false)

  defp scope_verdict(%Answer{verdict: :allow}), do: :scoped
  defp scope_verdict(%Answer{verdict: :deny}), do: :deny

  defp closed(%Error.Engine{detail: detail}) do
    %Answer{verdict: :deny, reason: Reason.engine_unreachable(detail), policy_version: nil, applied_position: nil}
  end

  defp unknown_kind(%Subject{kind: kind}) do
    %Answer{verdict: :deny, reason: Reason.unknown_subject_kind(kind), policy_version: nil, applied_position: nil}
  end

  # A batch's one answer: allowed when every object is, denied otherwise.
  defp summary(verdicts) do
    if map_size(verdicts) > 0 and Enum.all?(verdicts, fn {_ref, verdict} -> verdict == :allow end) do
      %Answer{verdict: :allow, reason: Reason.allowed("batch"), policy_version: nil, applied_position: nil}
    else
      %Answer{verdict: :deny, reason: Reason.deny_by_default(), policy_version: nil, applied_position: nil}
    end
  end

  defp stamp(call, subject, operation, ref, %Answer{} = answer, verdict) do
    head = head_position(call.head)

    %Decision{
      id: Id.new(),
      subject: subject,
      object: ref,
      operation: operation,
      verdict: verdict,
      reason: answer.reason,
      adapter: call.adapter,
      policy_version: answer.policy_version,
      head_position: head,
      applied_position: answer.applied_position || head,
      operation_id: call.operation_id,
      at: call.environment.now
    }
  end

  # The span: the attempt at :start, the decision at :stop. `fun` returns
  # the call's result, the decision or nil, and extra metadata.
  defp span(call, subject, operation, ref, fun) do
    metadata = %{
      subject: Subject.to_map(subject),
      subject_kind: call.kind,
      operation: operation,
      object: ref,
      operation_id: call.operation_id,
      head_position: head_position(call.head),
      adapter: call.adapter
    }

    :telemetry.span([:turnstile, call.kind], metadata, fn ->
      {result, decision, extra} = fun.()
      stop = Map.put(metadata, :decision, decision_out(decision))
      {result, Map.merge(stop, extra)}
    end)
  end

  defp head_position({:ok, head}), do: head
  defp head_position({:error, _error}), do: nil

  defp decision_out(nil), do: nil
  defp decision_out(%Decision{} = decision), do: Decision.to_map(decision)

  defp population_type([%Object{type: type} | _rest]), do: type
  defp population_type(type) when is_atom(type), do: type
  defp population_type([]), do: nil

  defp ids(refs, %Config{caps: caps}) do
    ids =
      refs
      |> Enum.map(fn {_type, id} -> id end)
      |> Enum.sort()

    if length(ids) > Keyword.fetch!(caps, :batch_ids) do
      joined = Enum.map_join(ids, "\n", &to_string/1)
      %{count: length(ids), sha256: sha256(joined)}
    else
      ids
    end
  end

  defp rule_text(rule, %Config{caps: caps}) do
    text = inspect(rule)
    limit = Keyword.fetch!(caps, :rule_bytes)

    if byte_size(text) > limit do
      %{text: binary_part(text, 0, limit), truncated: true, sha256: sha256(text)}
    else
      %{text: text, truncated: false, sha256: sha256(text)}
    end
  end

  defp review_value_out(refs) when is_list(refs), do: refs
  defp review_value_out(rule), do: inspect(rule)

  defp sha256(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  defp not_authorized(subject, operation, object, reason) do
    %Error.NotAuthorized{subject: subject, operation: operation, object: object, reason: reason}
  end

  defp config! do
    case Config.resolve() do
      {:ok, config} -> config
      {:error, error} -> raise error
    end
  end
end
