defmodule Turnstile.Rbac do
  @moduledoc """
  RBAC in code: the adapter whose rules are Elixir modules. A policy module,
  `use Turnstile.Rbac.Policy`, declares the role table as data and, per
  protected schema, the grants that hold a role on its rows and the
  predicates every allowed row must satisfy; the predicates are functions in
  the same modules. The adapter takes no options, so its configuration entry
  is the bare module, and it finds the policy and the repo through the
  binding `Turnstile.Rbac.Binding.bind/1` makes at boot beside the
  configuration.

  Every answer is a query the repo runs at the time of the call. `scope`
  returns the rule as a `dynamic` over subqueries and runs nothing itself;
  `decide` runs one query that selects each clause of the rule for the row
  asked about, so the reason names the clause that allowed or the clause
  that failed, and the clauses that held travel on the answer's `meta`. A
  deploy is a policy version, and `publish/0` emits it as telemetry at
  boot.
  """

  @behaviour Turnstile.Adapter

  use Boundary,
    deps: [Turnstile, Ecto, NimbleOptions],
    check: [apps: [:ecto_sql, :postgrex]],
    exports: [
      Binding,
      Coverage,
      Domain.Clauses,
      Policy,
      Policy.Clause,
      Policy.Object,
      Policy.Role,
      Version
    ]

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Error
  alias Turnstile.PolicyVersion
  alias Turnstile.Rbac.Binding
  alias Turnstile.Rbac.Infrastructure.Decide
  alias Turnstile.Rbac.Infrastructure.Rule
  alias Turnstile.Rbac.Infrastructure.Version

  @doc "Emit the bound policy's version as telemetry; the version is `Turnstile.Rbac.Version`."
  @spec publish() :: {:ok, PolicyVersion.t()} | {:error, Error.t()}
  def publish, do: Version.publish(__MODULE__)

  @impl Turnstile.Adapter
  def scope_cap, do: :none

  @impl Turnstile.Adapter
  def decide({_kind, _account} = subject, operation, {_type, _id} = object, %{now: _now} = environment, _options)
      when is_atom(operation) do
    with {:ok, %Binding{} = binding} <- bound(:decide) do
      named(Decide.one(binding, subject, operation, object, environment), :decide)
    end
  end

  @impl Turnstile.Adapter
  def scope({_kind, _account} = subject, operation, object_type, %{now: _now} = environment, _options)
      when is_atom(operation) and is_atom(object_type) do
    with {:ok, %Binding{} = binding} <- bound(:scope) do
      scoped(Rule.build(binding.policy, subject, operation, object_type, environment))
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
