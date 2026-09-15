defmodule Turnstile.Adapter do
  @moduledoc """
  The contract every adapter implements. The port calls these with a subject,
  an operation, an object or object type, the environment, and the adapter's
  validated options; the adapter answers and never raises on the request
  path. `around_query/3`, `options_schema/0`, and `settle/0` are optional
  and answered at runtime: the port and the seam check whether the adapter
  exports them, so one build serves every adapter. What produced an answer,
  where the adapter can say, travels on the answer's `meta`.

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

  @doc "Decide for one object; the port records it, whether the caller asked `authorize` or `check`."
  @callback decide(Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment(), options()) ::
              {:ok, Answer.t()} | failure()

  @doc "The rule that narrows a query over an object type to what the subject may see."
  @callback scope(Turnstile.subject(), atom(), atom(), Turnstile.environment(), options()) ::
              {:ok, scoped()} | failure()

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

  @optional_callbacks around_query: 3, options_schema: 0, settle: 0
end
