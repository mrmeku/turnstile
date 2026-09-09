defmodule Turnstile.Cerbos.Decide do
  @moduledoc """
  The answers the adapter gives: the attribute values read, one request to
  the sidecar, and the effects it answered turned into answers.

  A decision over rows is one call carrying every object asked about, and a
  scope is one call for the object type whose filter becomes the rule. An
  effect of allow is allowed by the policy the sidecar matched; anything
  else is a denial naming that policy where the sidecar named one. A denial
  is not read as a rule that denied, because the sidecar names the policy it
  evaluated whether a rule denied or no rule allowed, and the two are not
  the same claim.

  A resource the sidecar answered nothing about is denied by default, and a
  failure of the call is the failure's detail, which the adapter turns into
  an engine error.

  Each call carries the request-time facts with the subject's attributes, so
  a rule about the moment of the request is answered from the moment the
  port stamped it with rather than from the sidecar's own clock
  (`Turnstile.Cerbos.Values.environment/2`).
  """

  import Ecto.Query, only: [dynamic: 2]

  alias Turnstile.Answer
  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Client
  alias Turnstile.Cerbos.Plan
  alias Turnstile.Cerbos.Request
  alias Turnstile.Cerbos.Values
  alias Turnstile.Environment
  alias Turnstile.Explanation
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Scope
  alias Turnstile.Subject

  @fallback [:turnstile, :cerbos, :scope_fallback]

  @doc "The telemetry event a plan this adapter cannot express emits, once per scope that falls back."
  @spec fallback_event() :: [atom()]
  def fallback_event, do: @fallback

  @doc "The explanation for one object: its answer and the policy the sidecar matched."
  @spec one(Binding.t(), Client.address(), Subject.t(), atom(), Object.t(), Environment.t()) ::
          {:ok, Explanation.t()} | {:error, String.t()}
  def one(%Binding{} = binding, address, %Subject{} = subject, operation, %Object{} = object, %Environment{} = request)
      when is_binary(address) and is_atom(operation) do
    with {:ok, explained} <- explained(binding, address, subject, operation, [object], request) do
      {:ok, Map.fetch!(explained, Object.ref(object))}
    end
  end

  @doc "The answers for a list of objects, one per object reference."
  @spec many(Binding.t(), Client.address(), Subject.t(), atom(), [Object.t()], Environment.t()) ::
          {:ok, %{Object.ref() => Answer.t()}} | {:error, String.t()}
  def many(%Binding{} = binding, address, %Subject{} = subject, operation, objects, %Environment{} = request)
      when is_binary(address) and is_atom(operation) and is_list(objects) do
    with {:ok, explained} <- explained(binding, address, subject, operation, objects, request) do
      {:ok, Map.new(explained, fn {ref, %Explanation{answer: answer}} -> {ref, answer} end)}
    end
  end

  @doc """
  The rule for an object type: the plan the sidecar answered compiled
  against the declarations. A plan that admits no row is a denial with the
  rule that admits none, and a plan this adapter does not express emits
  `fallback_event/0` and fails, which is what a caller records as limited.
  """
  @spec scoped(Binding.t(), Client.address(), Subject.t(), atom(), atom(), Environment.t()) ::
          {:ok, Scope.t()} | {:error, String.t()}
  def scoped(%Binding{} = binding, address, %Subject{} = subject, operation, kind, %Environment{} = request)
      when is_binary(address) and is_atom(operation) and is_atom(kind) do
    with {:ok, principal} <- Values.principal(binding, subject, request),
         body = Request.plan(subject, operation, kind, principal),
         {:ok, answered} <- Client.plan_resources(address, body) do
      compiled(binding, subject, operation, kind, answered)
    end
  end

  @doc "The policy the sidecar matched for an action of one result, or `nil` where it matched none."
  @spec matched(map(), String.t()) :: String.t() | nil
  def matched(result, action) when is_map(result) and is_binary(action) do
    case result["meta"]["actions"][action]["matchedPolicy"] do
      "NO_MATCH" -> nil
      policy -> policy
    end
  end

  @doc """
  The answer an effect makes under a policy version: allowed by the policy
  the sidecar matched, or denied by default naming the policy that answered.
  """
  @spec answer(String.t() | nil, String.t() | nil, String.t() | nil) :: Answer.t()
  def answer("EFFECT_ALLOW", policy, version) do
    %Answer{verdict: :allow, reason: Reason.allowed(policy), policy_version: version, applied_position: nil}
  end

  def answer(_effect, policy, version) do
    reason = %{Reason.deny_by_default() | rule: policy}
    %Answer{verdict: :deny, reason: reason, policy_version: version, applied_position: nil}
  end

  defp compiled(binding, subject, operation, kind, answered) do
    case Plan.dynamic(binding, subject, kind, Map.get(answered, "filter", %{})) do
      {:ok, rule} -> {:ok, %Scope{rule: rule, answer: allowed(binding, nil)}}
      :denied -> {:ok, %Scope{rule: dynamic([_row], false), answer: denied(binding, nil)}}
      {:error, detail} -> fallback(operation, kind, detail)
    end
  end

  defp fallback(operation, kind, detail) do
    :telemetry.execute(@fallback, %{}, %{operation: operation, kind: kind, detail: detail})
    {:error, detail}
  end

  defp explained(binding, address, subject, operation, objects, request) do
    with {:ok, principal} <- Values.principal(binding, subject, request),
         {:ok, paired} <- paired(binding, subject, objects),
         body = Request.check(subject, operation, principal, paired),
         {:ok, answered} <- Client.check_resources(address, body),
         {:ok, effects} <- effects(answered, operation) do
      {:ok, Map.new(objects, &{Object.ref(&1), explanation(binding, Map.get(effects, key(&1)))})}
    end
  end

  # Each object with the values read for its own type, in the order asked.
  defp paired(binding, subject, objects) do
    step = fn {kind, of_kind}, {:ok, acc} -> gathered(binding, subject, kind, of_kind, acc) end

    with {:ok, by_object} <- Enum.reduce_while(Enum.group_by(objects, & &1.type), {:ok, %{}}, step) do
      {:ok, Enum.map(objects, &{&1, Map.fetch!(by_object, key(&1))})}
    end
  end

  defp gathered(binding, subject, kind, objects, acc) do
    case Values.resources(binding, subject, kind, objects) do
      {:ok, by_id} -> {:cont, {:ok, Map.merge(acc, Map.new(objects, &{key(&1), Map.get(by_id, to_string(&1.id), %{})}))}}
      {:error, detail} -> {:halt, {:error, detail}}
    end
  end

  # The effect and the matched policy of each resource the sidecar answered
  # about, by kind and id, which is how a resource is named in the answer.
  defp effects(%{"results" => results}, operation) when is_list(results) do
    action = Atom.to_string(operation)
    {:ok, Map.new(results, &{resource_key(&1), {effect(&1, action), matched(&1, action)}})}
  end

  defp effects(other, _operation) do
    {:error, "cerbos answered no results: " <> String.slice(inspect(other), 0, 200)}
  end

  defp resource_key(result), do: {result["resource"]["kind"], result["resource"]["id"]}

  defp effect(result, action), do: result["actions"][action]

  defp key(%Object{type: type, id: id}), do: {Atom.to_string(type), to_string(id)}

  defp explanation(binding, {"EFFECT_ALLOW", policy}) do
    %Explanation{answer: allowed(binding, policy), matched: List.wrap(policy)}
  end

  defp explanation(binding, {_effect, policy}), do: %Explanation{answer: denied(binding, policy), matched: []}
  defp explanation(binding, nil), do: %Explanation{answer: denied(binding, nil), matched: []}

  defp allowed(%Binding{commit: commit}, policy), do: answer("EFFECT_ALLOW", policy, commit)

  # The sidecar names the policy it evaluated on a denial as it does on an
  # allowance, so the reason is that no rule allowed, with the policy that
  # answered named.
  defp denied(%Binding{commit: commit}, policy), do: answer(nil, policy, commit)
end
