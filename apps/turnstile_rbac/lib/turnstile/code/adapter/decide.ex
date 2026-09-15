defmodule Turnstile.Code.Adapter.Decide do
  @moduledoc false
  # The answer `decide` gives: one query that selects every clause of the
  # rule for the row asked about, through the bound repo as a library
  # caller. A row that is not there is denied by default, as is a subject
  # no grant reaches; a row a grant reaches that fails a predicate is denied
  # by that predicate's name; a row every clause allows is allowed by the
  # first grant that held. A predicate that answers with neither a
  # `dynamic` nor a boolean is its detail, and the adapter names the
  # callback it failed in.
  #
  # A repo that raises is left to raise. The port turns any exception a
  # decider raises into a denial with `engine_unreachable`, so this package
  # names no driver's error, and a driver it does not carry needs no clause
  # of its own.

  import Ecto.Query, only: [from: 2]

  alias Turnstile.Answer
  alias Turnstile.Code.Binding
  alias Turnstile.Code.Core.Rule

  @doc "The answer for one object, with the clauses that held under `meta[:matched]`."
  @spec one(Binding.t(), Turnstile.subject(), atom(), Turnstile.object(), Turnstile.environment()) ::
          {:ok, Answer.t()} | {:error, String.t()}
  def one(%Binding{} = binding, {_kind, _account} = subject, operation, {type, id}, %{now: _now} = environment) do
    case Rule.build(binding.policy, subject, operation, type, environment) do
      {:ok, %Rule{} = rule} -> {:ok, answered(rule, row(binding.repo, rule, id))}
      {:error, %Answer{} = answer} -> {:ok, matched(answer, [])}
      {:error, detail} when is_binary(detail) -> {:error, detail}
    end
  end

  defp row(repo, %Rule{schema: schema} = rule, id) do
    key = Rule.primary_key(schema)
    query = from(row in schema, where: field(row, ^key) == ^id, select: ^Rule.clauses(rule))
    repo.one(query, turnstile: {:exempt, :library})
  end

  defp answered(%Rule{version: version}, nil), do: matched(Rule.deny(:deny_by_default, version), [])

  defp answered(%Rule{grants: grants, predicates: predicates, version: version}, row) do
    held = fn {name, _expression} -> row[name] == true end
    held_names = for {name, _expression} = clause <- grants ++ predicates, held.(clause), do: name
    answer = answer(Enum.find(grants, held), Enum.reject(predicates, held), version)
    matched(answer, held_names)
  end

  defp answer(nil, _failed, version), do: Rule.deny(:deny_by_default, version)

  defp answer(_granted, [{name, _expression} | _rest], version) do
    Rule.deny(:rule_denied, version, %{rule: Atom.to_string(name)})
  end

  defp answer({name, _expression}, [], version) do
    %Answer{verdict: :allow, reason: :allowed, version: version, meta: %{rule: Atom.to_string(name)}}
  end

  # What held, on the answer the decider gives back.
  defp matched(%Answer{} = answer, names), do: %{answer | meta: Map.put(answer.meta, :matched, names)}
end
