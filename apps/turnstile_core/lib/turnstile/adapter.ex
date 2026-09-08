defmodule Turnstile.Adapter do
  @moduledoc """
  The contract every adapter implements. The port calls these with a subject,
  an operation, an object or object type, the environment, and the adapter's
  validated options; the adapter answers and never raises on the request
  path. `explain/5` and `around_query/3` are optional and answered at runtime:
  the port checks whether the adapter exports them and returns
  `Turnstile.Error.Unsupported` when it does not, so one build serves every
  adapter.

  Two declarations are true of an adapter in any domain: whether it requires
  a ledger, and the cap on the number of objects `scope` can return, `:none`
  where the rule is a query the database runs.
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
  Wrap the query a decision admits. The adapter that needs session state at
  execution, such as row-level security settings, sets it here and calls the
  function; every other adapter leaves this undefined and the seam calls the
  function directly.
  """
  @callback around_query(Decision.t(), Ecto.Query.t(), (-> term())) :: term()

  @doc "The schema for the adapter's entry in `Turnstile.Config`. Absent, the entry must be the bare module."
  @callback options_schema() :: NimbleOptions.t()

  @doc "Whether the adapter can be bound without a ledger."
  @callback requires_ledger() :: boolean()

  @doc "The cap on objects `scope` can return, or `:none`."
  @callback scope_cap() :: pos_integer() | :none

  @optional_callbacks explain: 5, around_query: 3, options_schema: 0
end
