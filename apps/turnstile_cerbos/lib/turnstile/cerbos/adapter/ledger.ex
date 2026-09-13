defmodule Turnstile.Cerbos.Adapter.Ledger do
  @moduledoc false
  # Appending the policy version to the ledger: read the latest version the
  # ledger holds for the adapter, page by page from the start, and append
  # when it names an older version or none, inside the ledger's transaction
  # when the ledger offers one, so many nodes booting at once append it
  # once. In ledger mode none the telemetry event is emitted and nothing is
  # appended. What a version is, and what it holds, is
  # `Turnstile.Cerbos.Version`'s.

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Version
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.PolicyVersion

  @page 1_000

  @doc """
  Append the bound commit as a version when the ledger's latest is older or
  missing: `{:ok, event}` when appended, `{:ok, :current}` when the ledger
  already names it, `{:ok, :telemetry}` in ledger mode none.
  """
  @spec publish(module()) :: {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.t()}
  def publish(adapter) when is_atom(adapter) do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve(),
         {:ok, %PolicyVersion{} = version} <- Version.of(adapter, binding, config, config.clock.()) do
      result = published(version, config.ledger)
      :telemetry.execute(Version.telemetry_event(), %{}, %{version: version, result: elem(result, 1)})
      result
    end
  end

  defp published(%PolicyVersion{}, :none), do: {:ok, :telemetry}

  defp published(%PolicyVersion{adapter: adapter} = version, {ledger, options}) do
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
