defmodule Turnstile.Cerbos.Decisions do
  @moduledoc """
  The sidecar's decision log read back and set beside what the port
  recorded, so a reviewer can see that the two agree.

  Two records of the same answers exist because two things wrote them: the
  sidecar decided, and the port stamped what it was told. A review that
  reads one alone is a review of one side's word. Reconciliation reads both
  and reports every difference: a decision the log holds that no record
  matches, a record no line holds, and a pair that agree on who asked what
  and disagree on the answer (`Turnstile.Cerbos.Finding`).

  Matching is on who asked, what operation, and which object, since the
  sidecar is never told the identifier the port gave the call. A line about
  a query plan carries no object identifier, which is the shape the port
  stamps for a `scope`, so the two meet there too. Where a subject asked the
  same question twice, each line takes one record, in the order both were
  written.

  The log's path comes from the binding, and reading it is the caller's
  move rather than something that happens on the request path: nothing here
  runs while a decision is being made.
  """

  alias Turnstile.Cerbos.Decisions.Line
  alias Turnstile.Cerbos.Finding
  alias Turnstile.Decision
  alias Turnstile.Error

  @doc "Every answer the log at the path holds, in the order the file holds them."
  @spec lines(Path.t()) :: {:ok, [Line.t()]} | {:error, Error.Invalid.t()}
  def lines(path) when is_binary(path) do
    with {:ok, text} <- read(path) do
      parsed(text, path)
    end
  end

  @doc "Every difference between the log at the path and the decisions the port recorded."
  @spec reconcile(Path.t(), [Decision.t()]) :: {:ok, [Finding.t()]} | {:error, Error.Invalid.t()}
  def reconcile(path, decisions) when is_binary(path) and is_list(decisions) do
    with {:ok, lines} <- lines(path) do
      {found, left} = Enum.map_reduce(lines, Enum.group_by(decisions, &key/1), &compared/2)
      {:ok, Enum.reject(found, &is_nil/1) ++ unlogged(left)}
    end
  end

  defp read(path) do
    case File.read(path) do
      {:ok, text} -> {:ok, text}
      {:error, reason} -> {:error, invalid("cannot read the decision log at #{path}: #{message(reason)}")}
    end
  end

  # A log line is an edge: it is decoded, and a line that is no JSON object
  # is a log this module refuses to read rather than one it reads in part.
  defp parsed(text, path) do
    numbered = Enum.with_index(String.split(text, "\n", trim: true), 1)
    step = fn {raw, number}, {:ok, taken} -> decoded(raw, number, path, taken) end

    with {:ok, taken} <- Enum.reduce_while(numbered, {:ok, []}, step) do
      {:ok, List.flatten(Enum.reverse(taken))}
    end
  end

  defp decoded(raw, number, path, taken) do
    case JSON.decode(raw) do
      {:ok, map} when is_map(map) -> {:cont, {:ok, [Line.from_map(map, number) | taken]}}
      _no_object -> {:halt, {:error, invalid("line #{number} of #{path} is no JSON object")}}
    end
  end

  defp key(%Decision{} = decision) do
    {kind, id} = Finding.reference(decision.object)
    {to_string(decision.subject.id), Atom.to_string(decision.operation), kind, id}
  end

  defp compared(%Line{} = line, remaining) do
    case Map.get(remaining, Line.key(line), []) do
      [] -> {unrecorded(line), remaining}
      [decision | rest] -> {disagreement(line, decision), Map.put(remaining, Line.key(line), rest)}
    end
  end

  defp disagreement(%Line{verdict: verdict}, %Decision{verdict: verdict}), do: nil

  defp disagreement(%Line{} = line, %Decision{} = decision) do
    %Finding{
      kind: :verdict,
      subject: line.subject,
      operation: line.operation,
      object: {line.kind, line.id},
      line: line.number,
      logged: line.verdict,
      recorded: decision.verdict,
      decision: decision.id,
      policy: line.policy
    }
  end

  defp unrecorded(%Line{} = line) do
    %Finding{
      kind: :unrecorded,
      subject: line.subject,
      operation: line.operation,
      object: {line.kind, line.id},
      line: line.number,
      logged: line.verdict,
      recorded: nil,
      policy: line.policy
    }
  end

  defp unlogged(remaining) do
    for {_key, decisions} <- remaining, %Decision{} = decision <- decisions do
      {kind, id} = Finding.reference(decision.object)

      %Finding{
        kind: :unlogged,
        subject: to_string(decision.subject.id),
        operation: Atom.to_string(decision.operation),
        object: {kind, id},
        line: nil,
        logged: nil,
        recorded: decision.verdict,
        decision: decision.id
      }
    end
  end

  defp message(reason), do: to_string(:file.format_error(reason))

  defp invalid(detail), do: %Error.Invalid{what: :decision_log, detail: detail}
end
