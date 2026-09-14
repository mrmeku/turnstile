defmodule Turnstile.Adapter do
  @moduledoc """
  The contract every adapter implements. The port calls these with a subject,
  an operation, an object or object type, the environment, and the adapter's
  validated options; the adapter answers and never raises on the request
  path. `explain/5` and `around_query/3` are optional and answered at runtime:
  the port checks whether the adapter exports them and answers an error
  with the reason `:unsupported` when it does not, so one build serves every
  adapter. A rule that narrows and an answer that explains are the same two
  values everywhere: `scope/5` answers the rule with its answer, and
  `explain/5` answers with what matched on the answer's `meta`.

  Two declarations are true of an adapter in any domain: the cap on the
  number of objects `scope` can return, `:none` where the rule is a query
  the database runs, and whether it has state of its own to settle, which
  an adapter reading the application's own tables has not.
  """

  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Error

  @type options :: keyword()
  @type failure :: {:error, Error.t()}

  @typedoc "What `scope/5` answers: the rule as a dynamic, and the answer that goes with it."
  @type scoped :: {Ecto.Query.dynamic_expr(), Answer.t()}

  @doc "Decide, and let the port record the decision."
  @callback authorize(Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment(), options()) ::
              {:ok, Answer.t()} | failure()

  @doc "Decide without a record; the port records `check` as it records `authorize`, the adapter need not tell them apart."
  @callback check(Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment(), options()) ::
              {:ok, Answer.t()} | failure()

  @doc "Decide for many objects of one type at once, one answer per object reference."
  @callback batch(Turnstile.subject(), atom(), [Turnstile.object()], Turnstile.environment(), options()) ::
              {:ok, %{Turnstile.object() => Answer.t()}} | failure()

  @doc "The rule that narrows a query over an object type to what the subject may see."
  @callback scope(Turnstile.subject(), atom(), atom(), Turnstile.environment(), options()) ::
              {:ok, scoped()} | failure()

  @doc "The answer with what produced it under `meta[:matched]`, where the adapter can say."
  @callback explain(Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment(), options()) ::
              {:ok, Answer.t()} | {:error, Error.t()}

  @doc """
  Wrap a mediated call: the query or changeset, the decision in force, and
  the zero-arity function that runs the call. The adapter that needs session
  state at execution, such as row-level security settings, sets it here and
  calls the function; every other adapter leaves this undefined and the seam
  calls the function directly.
  """
  @callback around_query(Ecto.Query.t() | Ecto.Changeset.t(), Decision.t(), (-> term())) :: term()

  @doc "The schema for the adapter's entry in `Turnstile.Config`. Absent, the entry must be the bare module."
  @callback options_schema() :: NimbleOptions.t()

  @doc "The cap on objects `scope` can return, or `:none`."
  @callback scope_cap() :: pos_integer() | :none

  @doc """
  Bring whatever state the adapter keeps of its own into step with the
  application's tables, and answer when nothing is outstanding. `:none` for
  an adapter that keeps none, which is what an adapter leaving this callback
  undefined says. A caller that has written facts and is about to ask about
  them settles first; `Turnstile.Test.settle/0` is that caller in the suite.

  Settling is what a caller does in place of waiting. An application in
  production has a process bringing the same state into step on its own
  interval, and nothing on the request path calls this.
  """
  @callback settle() :: :ok | :none | {:error, Error.t()}

  @optional_callbacks explain: 5, around_query: 3, options_schema: 0, settle: 0
end
