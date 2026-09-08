defmodule Turnstile.Code.Decide do
  @moduledoc """
  The answers `check`, `authorize`, `batch`, and `explain` give: one query
  per object type that selects every clause of the rule for the rows asked
  about, through the bound repo as a library caller. A row that is not
  there is denied by default, as is a subject no grant reaches; a row a
  grant reaches that fails a predicate is denied by that predicate's name;
  a row every clause allows is allowed by the first grant that held. A
  failure is its detail; the adapter names the callback it failed in.
  """

  import Ecto.Query, only: [dynamic: 2, from: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Rule
  alias Turnstile.Environment
  alias Turnstile.Explanation
  alias Turnstile.Object
  alias Turnstile.Reason
  alias Turnstile.Subject

  @doc "The explanation for one object: its answer and the clauses that held."
  @spec one(Binding.t(), Subject.t(), atom(), Object.t(), Environment.t()) ::
          {:ok, Explanation.t()} | {:error, String.t()}
  def one(%Binding{} = binding, %Subject{} = subject, operation, %Object{} = object, %Environment{} = environment) do
    with {:ok, [{^object, explanation}]} <- explained(binding, subject, operation, [object], environment) do
      {:ok, explanation}
    end
  end

  @doc "The answers for a list of objects, one per object reference."
  @spec many(Binding.t(), Subject.t(), atom(), [Object.t()], Environment.t()) ::
          {:ok, %{Object.ref() => Answer.t()}} | {:error, String.t()}
  def many(%Binding{} = binding, %Subject{} = subject, operation, objects, %Environment{} = environment) do
    with {:ok, explained} <- explained(binding, subject, operation, objects, environment) do
      {:ok, Map.new(explained, fn {object, %Explanation{answer: answer}} -> {Object.ref(object), answer} end)}
    end
  end

  defp explained(binding, subject, operation, objects, environment) do
    grouped = Enum.group_by(objects, & &1.type)
    step = fn {type, of_type}, acc -> merge(of_type(binding, subject, operation, type, of_type, environment), acc) end

    with {:ok, by_object} <- Enum.reduce_while(grouped, {:ok, %{}}, step) do
      {:ok, Enum.map(objects, &{&1, Map.fetch!(by_object, &1)})}
    end
  end

  defp merge({:ok, explained}, {:ok, acc}), do: {:cont, {:ok, Map.merge(acc, explained)}}
  defp merge({:error, _error} = error, _acc), do: {:halt, error}

  defp of_type(binding, subject, operation, type, objects, environment) do
    case Rule.build(binding.policy, subject, operation, type, environment) do
      {:ok, %Rule{} = rule} -> queried(binding.repo, rule, objects)
      {:error, %Answer{} = answer} -> {:ok, Map.new(objects, &{&1, %Explanation{answer: answer, matched: []}})}
      {:error, detail} when is_binary(detail) -> {:error, detail}
    end
  end

  defp queried(repo, %Rule{} = rule, objects) do
    with {:ok, rows} <- rows(repo, rule, objects) do
      {:ok, Map.new(objects, &{&1, explain(rule, Map.get(rows, key(&1)))})}
    end
  end

  defp rows(repo, %Rule{schema: schema} = rule, objects) do
    key = Rule.primary_key(schema)
    ids = Enum.map(objects, & &1.id)
    selected = Map.put(Rule.clauses(rule), :__key__, dynamic([row], field(row, ^key)))
    query = from(row in schema, where: field(row, ^key) in ^ids, select: ^selected)

    {:ok, Map.new(repo.all(query, turnstile: {:exempt, :library}), &{to_string(&1.__key__), &1})}
  rescue
    error in [DBConnection.ConnectionError, Postgrex.Error] -> {:error, Exception.message(error)}
  end

  defp key(%Object{id: id}), do: to_string(id)

  defp explain(%Rule{version: version}, nil) do
    %Explanation{answer: Rule.deny(Reason.deny_by_default(), version), matched: []}
  end

  defp explain(%Rule{grants: grants, predicates: predicates, version: version}, row) do
    held = fn {name, _expression} -> row[name] == true end
    matched = for {name, _expression} = clause <- grants ++ predicates, held.(clause), do: name
    answer = answer(Enum.find(grants, held), Enum.reject(predicates, held), version)
    %Explanation{answer: answer, matched: matched}
  end

  defp answer(nil, _failed, version), do: Rule.deny(Reason.deny_by_default(), version)

  defp answer(_granted, [{name, _expression} | _rest], version) do
    reason = Reason.rule_denied(Atom.to_string(name))
    Rule.deny(reason, version)
  end

  defp answer({name, _expression}, [], version) do
    reason = Reason.allowed(Atom.to_string(name))
    %Answer{verdict: :allow, reason: reason, policy_version: version, applied_position: nil}
  end
end
