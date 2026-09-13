defmodule Turnstile.Postgres.Adapter.Ledger do
  @moduledoc false
  # Appending the policy version to the ledger: read the latest version the
  # ledger holds for the adapter, page by page from the start, and append
  # when it names an older version or none, inside the ledger's transaction
  # when the ledger offers one, so two migrations running at once append it
  # once. In ledger mode none the telemetry event is emitted and nothing is
  # appended. What a version is, and what it holds, is
  # `Turnstile.Postgres.Version`'s.

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Version

  @page 1_000

  @doc """
  Append the version unless the ledger's latest for the adapter already
  names it: `{:ok, event}` when appended, `{:ok, :current}` when it is
  already there, `{:ok, :telemetry}` in ledger mode none.
  """
  @spec publish(PolicyVersion.t(), :none | {module(), keyword()}) ::
          {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.t()}
  def publish(%PolicyVersion{} = version, ledger) do
    result = appended(version, ledger)
    :telemetry.execute(Version.telemetry_event(), %{}, %{version: version, result: elem(result, 1)})
    result
  end

  defp appended(%PolicyVersion{}, :none), do: {:ok, :telemetry}

  defp appended(%PolicyVersion{adapter: adapter} = version, {ledger, options}) do
    within(ledger, options, fn ->
      with {:ok, latest} <- latest(ledger, options, adapter) do
        append(ledger, options, version, latest)
      end
    end)
  end

  defp within(ledger, options, fun) do
    if function_exported?(ledger, :transaction, 2), do: ledger.transaction(options, fun), else: fun.()
  end

  defp append(_ledger, _options, %PolicyVersion{version: same}, %PolicyVersion{version: same}), do: {:ok, :current}

  defp append(ledger, options, %PolicyVersion{adapter: adapter} = version, previous) do
    event = %FactEvent{
      kind: :policy_version,
      subject_ref: nil,
      object_ref: {:policy, adapter},
      attribute: :version,
      old: previous && previous.version,
      new: version,
      position: nil,
      operation_id: Id.new(),
      at: version.at,
      by: FactEvent.library()
    }

    case ledger.append(options, [event]) do
      {:ok, [appended]} -> {:ok, appended}
      {:error, %Error{reason: :engine_unreachable} = error} -> {:error, error}
    end
  end

  # The latest policy version of the adapter in the ledger, paging from the start.
  defp latest(ledger, options, adapter), do: latest(ledger, options, adapter, 0, nil)

  defp latest(ledger, options, adapter, from, found) do
    case ledger.read(options, from, @page) do
      {:ok, []} -> {:ok, found}
      {:ok, events} -> latest(ledger, options, adapter, List.last(events).position, newest(events, adapter, found))
      {:error, %Error{reason: :engine_unreachable} = error} -> {:error, error}
    end
  end

  defp newest(events, adapter, found) do
    Enum.reduce(events, found, fn
      %FactEvent{kind: :policy_version, object_ref: {:policy, ^adapter}, new: %PolicyVersion{} = new}, _acc -> new
      _other, acc -> acc
    end)
  end
end
