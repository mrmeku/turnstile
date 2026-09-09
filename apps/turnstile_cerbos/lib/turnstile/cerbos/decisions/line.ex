defmodule Turnstile.Cerbos.Decisions.Line do
  @moduledoc """
  One question and answer out of the sidecar's decision log. The log is a
  file of JSON objects, one per line, and a line is an edge, so this module
  is where it becomes a struct.

  A line about resources carries the attributes as they were sent, and the
  roles the principal was sent with, which is what makes a replay possible
  without the state behind them, and one answer per resource and action, so
  one line becomes as many of these as it holds answers. A line about a query plan carries no resource id: it
  answers for the object type, and its verdict is that the type was scoped,
  or denied where the plan admits no row.
  """

  alias Turnstile.Decision

  @enforce_keys [:number, :subject, :operation, :kind, :id, :verdict]
  defstruct [:number, :subject, :operation, :kind, :id, :verdict, policy: nil, roles: [], principal: %{}, resource: %{}]

  @type t :: %__MODULE__{
          number: pos_integer(),
          subject: String.t(),
          operation: String.t(),
          kind: String.t(),
          id: String.t() | nil,
          verdict: Decision.verdict(),
          policy: String.t() | nil,
          roles: [String.t()],
          principal: map(),
          resource: map()
        }

  @doc "The answers one line of the log carries, none where the line is no decision."
  @spec from_map(map(), pos_integer()) :: [t()]
  def from_map(%{"checkResources" => %{"inputs" => inputs, "outputs" => outputs}}, number)
      when is_list(inputs) and is_list(outputs) do
    by_request = Map.new(inputs, &{&1["requestId"], &1})
    Enum.flat_map(outputs, &checked(&1, Map.get(by_request, &1["requestId"], %{}), number))
  end

  def from_map(%{"planResources" => %{"input" => input, "output" => output}}, number)
      when is_map(input) and is_map(output) do
    [planned(input, output, number)]
  end

  def from_map(_other, _number), do: []

  @doc "What the line answers about, as `Turnstile.Cerbos.Decisions` matches a record by it."
  @spec key(t()) :: {String.t(), String.t(), String.t(), String.t() | nil}
  def key(%__MODULE__{} = line), do: {line.subject, line.operation, line.kind, line.id}

  defp checked(output, input, number) do
    for {action, answer} <- Map.get(output, "actions", %{}) do
      %__MODULE__{
        number: number,
        subject: input["principal"]["id"],
        operation: action,
        kind: input["resource"]["kind"],
        id: output["resourceId"] || input["resource"]["id"],
        verdict: verdict(answer["effect"]),
        policy: policy(answer["policy"]),
        roles: input["principal"]["roles"] || [],
        principal: input["principal"]["attr"] || %{},
        resource: input["resource"]["attr"] || %{}
      }
    end
  end

  defp planned(input, output, number) do
    %__MODULE__{
      number: number,
      subject: input["principal"]["id"],
      operation: output["action"] || input["action"],
      kind: output["kind"] || input["resource"]["kind"],
      id: nil,
      verdict: scoped(output["filter"]),
      policy: nil,
      roles: input["principal"]["roles"] || [],
      principal: input["principal"]["attr"] || %{},
      resource: %{}
    }
  end

  defp verdict("EFFECT_ALLOW"), do: :allow
  defp verdict(_other), do: :deny

  defp scoped(%{"kind" => "KIND_ALWAYS_DENIED"}), do: :deny
  defp scoped(_other), do: :scoped

  defp policy("NO_MATCH"), do: nil
  defp policy(policy), do: policy
end
