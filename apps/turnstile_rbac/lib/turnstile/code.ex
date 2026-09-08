defmodule Turnstile.Code do
  @moduledoc """
  RBAC in code: the adapter whose rules are Elixir modules. A policy module,
  `use Turnstile.Code.Policy`, declares the role table as data and, per
  protected schema, the grants that hold a role on its rows and the
  predicates every allowed row must satisfy; the predicates are functions in
  the same modules. The adapter takes no options, so its configuration entry
  is the bare module, and it finds the policy and the repo through the
  binding `Turnstile.Code.Binding.bind/1` makes at boot beside the
  configuration.

  Every answer is a query the repo runs at the time of the call. `scope`
  returns the rule as a `dynamic` over subqueries and runs nothing itself;
  `check`, `authorize`, `batch`, and `explain` run one query per call that
  selects each clause of the rule for the rows asked about, so the reason
  names the clause that allowed or the clause that failed, and `explain`
  lists every clause that held. A deploy is a policy version:
  `publish/0` appends it at boot when the ledger's latest names an older
  one, and emits telemetry alone in ledger mode none.
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [Binding, Coverage, Decide, Policy, Policy.Clause, Policy.Object, Policy.Role, Rule, Version]

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Decide
  alias Turnstile.Code.Rule
  alias Turnstile.Code.Version
  alias Turnstile.Environment
  alias Turnstile.Error
  alias Turnstile.Explanation
  alias Turnstile.FactEvent
  alias Turnstile.Object
  alias Turnstile.Scope
  alias Turnstile.Subject

  @doc "Append the bound policy's version to the ledger when its latest names an older one; see `Turnstile.Code.Version`."
  @spec publish() :: {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.Invalid.t() | Error.Engine.t()}
  def publish, do: Version.publish(__MODULE__)

  @impl Turnstile.Adapter
  def requires_ledger, do: false

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def authorize(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, _options)
      when is_atom(operation) do
    with {:ok, %Binding{} = binding} <- bound(:authorize),
         {:ok, %Explanation{answer: answer}} <-
           named(Decide.one(binding, subject, operation, object, environment), :authorize) do
      {:ok, answer}
    end
  end

  @impl Turnstile.Adapter
  def check(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, options)
      when is_atom(operation) do
    authorize(subject, operation, object, environment, options)
  end

  @impl Turnstile.Adapter
  def batch(%Subject{} = subject, operation, objects, %Environment{} = environment, _options)
      when is_atom(operation) and is_list(objects) do
    with {:ok, %Binding{} = binding} <- bound(:batch) do
      named(Decide.many(binding, subject, operation, objects, environment), :batch)
    end
  end

  @impl Turnstile.Adapter
  def scope(%Subject{} = subject, operation, object_type, %Environment{} = environment, _options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, %Binding{} = binding} <- bound(:scope) do
      scoped(Rule.build(binding.policy, subject, operation, object_type, environment))
    end
  end

  @impl Turnstile.Adapter
  def explain(%Subject{} = subject, operation, %Object{} = object, %Environment{} = environment, _options)
      when is_atom(operation) do
    with {:ok, %Binding{} = binding} <- bound(:explain) do
      named(Decide.one(binding, subject, operation, object, environment), :explain)
    end
  end

  defp scoped({:ok, %Rule{} = rule}), do: {:ok, %Scope{rule: Rule.dynamic(rule), answer: Rule.answer(rule)}}
  defp scoped({:error, %Answer{verdict: :deny} = answer}), do: {:ok, %Scope{rule: dynamic([_row], false), answer: answer}}
  defp scoped({:error, detail}) when is_binary(detail), do: named({:error, detail}, :scope)

  # A failure's detail becomes the engine error, naming the callback that failed.
  defp named({:error, detail}, callback) when is_binary(detail) do
    {:error, %Error.Engine{adapter: __MODULE__, operation: callback, detail: detail}}
  end

  defp named(other, _callback), do: other

  defp bound(operation) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} ->
        {:ok, binding}

      {:error, %Error.Invalid{detail: detail}} ->
        {:error, %Error.Engine{adapter: __MODULE__, operation: operation, detail: detail}}
    end
  end
end
