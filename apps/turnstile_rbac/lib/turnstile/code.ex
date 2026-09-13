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
    exports: [
      Binding,
      Core.Clauses,
      Coverage,
      Policy,
      Policy.Clause,
      Policy.Object,
      Policy.Role,
      Version
    ]

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Adapter.Decide
  alias Turnstile.Code.Adapter.Version
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Core.Rule
  alias Turnstile.Error
  alias Turnstile.FactEvent

  @doc "Append the bound policy's version to the ledger when its latest names an older one; the version is `Turnstile.Code.Version`."
  @spec publish() :: {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.t()}
  def publish, do: Version.publish(__MODULE__)

  @impl Turnstile.Adapter
  def requires_ledger, do: false

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def authorize({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, _options)
      when is_atom(operation) do
    with {:ok, %Binding{} = binding} <- bound(:authorize) do
      named(Decide.one(binding, subject, operation, object, environment), :authorize)
    end
  end

  @impl Turnstile.Adapter
  def check({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, options)
      when is_atom(operation) do
    authorize(subject, operation, object, environment, options)
  end

  @impl Turnstile.Adapter
  def batch({_kind, _account} = subject, operation, objects, %{now: _now} = environment, _options)
      when is_atom(operation) and is_list(objects) do
    with {:ok, %Binding{} = binding} <- bound(:batch) do
      named(Decide.many(binding, subject, operation, objects, environment), :batch)
    end
  end

  @impl Turnstile.Adapter
  def scope({_kind, _account} = subject, operation, object_type, %{now: _now} = environment, _options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, %Binding{} = binding} <- bound(:scope) do
      scoped(Rule.build(binding.policy, subject, operation, object_type, environment))
    end
  end

  @impl Turnstile.Adapter
  def explain({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, _options)
      when is_atom(operation) do
    with {:ok, %Binding{} = binding} <- bound(:explain) do
      named(Decide.one(binding, subject, operation, object, environment), :explain)
    end
  end

  defp scoped({:ok, %Rule{} = rule}), do: {:ok, {Rule.dynamic(rule), Rule.answer(rule)}}
  defp scoped({:error, %Answer{verdict: :deny} = answer}), do: {:ok, {dynamic([_row], false), answer}}
  defp scoped({:error, detail}) when is_binary(detail), do: named({:error, detail}, :scope)

  # A failure's detail becomes the engine error, naming the callback that failed.
  defp named({:error, detail}, callback) when is_binary(detail) do
    {:error, %Error{reason: :engine_unreachable, detail: "#{inspect(__MODULE__)} failed during #{callback}: #{detail}"}}
  end

  defp named(other, _callback), do: other

  defp bound(operation) do
    case Binding.resolve() do
      {:ok, %Binding{} = binding} ->
        {:ok, binding}

      {:error, %Error{reason: :invalid, detail: detail}} ->
        {:error,
         %Error{reason: :engine_unreachable, detail: "#{inspect(__MODULE__)} failed during #{operation}: #{detail}"}}
    end
  end
end
