defmodule Turnstile.Adapter do
  @moduledoc """
  The contract every adapter implements. The port calls these with a subject,
  an operation, an object or object type, the environment, and the adapter's
  validated options; the adapter answers and never raises on the request
  path. `explain/5` and `around_query/3` are optional and answered at runtime:
  the port checks whether the adapter exports them and returns
  `Turnstile.Error.Unsupported` when it does not, so one build serves every
  adapter.

  Three declarations are true of an adapter in any domain: whether it
  requires a ledger, the cap on the number of objects `scope` can return,
  `:none` where the rule is a query the database runs, and the projection it
  keeps, `:none` where the working state is the application's own tables.
  """

  alias Turnstile.Answer
  alias Turnstile.Decision
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.Object
  alias Turnstile.Scope
  alias Turnstile.Subject

  @type options :: keyword()
  @type failure :: {:error, Error.Engine.t()}

  @doc "Decide, and let the port record the decision."
  @callback authorize(Subject.t(), atom(), Object.t(), Environment.t(), options()) :: {:ok, Answer.t()} | failure()

  @doc "Decide without a record; the port records `check` as it records `authorize`, the adapter need not tell them apart."
  @callback check(Subject.t(), atom(), Object.t(), Environment.t(), options()) :: {:ok, Answer.t()} | failure()

  @doc "Decide for many objects of one type at once, one answer per object reference."
  @callback batch(Subject.t(), atom(), [Object.t()], Environment.t(), options()) ::
              {:ok, %{Object.ref() => Answer.t()}} | failure()

  @doc "The rule that narrows a query over an object type to what the subject may see."
  @callback scope(Subject.t(), atom(), atom(), Environment.t(), options()) :: {:ok, Scope.t()} | failure()

  @doc "The answer with what produced it, where the adapter can say."
  @callback explain(Subject.t(), atom(), Object.t(), Environment.t(), options()) ::
              {:ok, Explanation.t()} | {:error, Error.Unsupported.t() | Error.Engine.t()}

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

  @doc "Whether the adapter can be bound without a ledger."
  @callback requires_ledger() :: boolean()

  @doc "The cap on objects `scope` can return, or `:none`."
  @callback scope_cap() :: pos_integer() | :none

  @doc """
  The projection the adapter keeps: the module implementing
  `Turnstile.Projection` and the configuration that module's callbacks take,
  resolved the way the adapter resolves the rest of its state. `:none` for an
  adapter that projects nothing, which is what an adapter leaving this
  callback undefined says. A caller with facts to settle drains this to the
  ledger's head; `Turnstile.Test.settle/0` is that caller in the suite.
  """
  @callback projection() :: {:ok, {module(), struct()}} | :none | {:error, Error.Invalid.t() | Error.Unsupported.t()}

  @optional_callbacks explain: 5, around_query: 3, options_schema: 0, projection: 0
end
