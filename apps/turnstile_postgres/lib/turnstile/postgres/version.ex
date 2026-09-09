defmodule Turnstile.Postgres.Version do
  @moduledoc """
  The policy version of row-level security: the migration number. A
  migration that changes a policy appends its own version in the same
  transaction as its DDL, so the rules and the record of what they became
  commit together or not at all, and a decision made afterwards names that
  number.

  The content is the policies as `pg_policy` renders them, carried by value
  when it is under the cap the caller gives and left as a pointer to the
  tables above it. The content hash is the SHA-256 of that text either way.
  """

  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.PolicyVersion
  alias Turnstile.Postgres.Catalog
  alias Turnstile.Postgres.Policy
  alias Turnstile.Subject

  @page 1_000
  @telemetry [:turnstile, :postgres, :policy_version]

  @doc "The telemetry event `publish/2` emits in ledger mode none."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc """
  The version a migration publishes, from the policies it read back.
  Requires `version:`, `author:`, `approval:`, `at:`, and `content_bytes:`.
  """
  @spec of(module(), [Policy.t()], keyword()) :: PolicyVersion.t()
  def of(adapter, policies, options) when is_atom(adapter) and is_list(policies) and is_list(options) do
    text = Catalog.to_text(policies)
    carried? = byte_size(text) <= Keyword.fetch!(options, :content_bytes)

    %PolicyVersion{
      adapter: adapter,
      version: to_string(Keyword.fetch!(options, :version)),
      content_hash: Base.encode16(:crypto.hash(:sha256, text), case: :lower),
      content: if(carried?, do: text),
      pointer: if(carried?, do: nil, else: pointer(policies)),
      author: Keyword.fetch!(options, :author),
      approval: Keyword.fetch!(options, :approval),
      at: Keyword.fetch!(options, :at)
    }
  end

  @doc """
  Append the version unless the ledger's latest for the adapter already
  names it: `{:ok, event}` when appended, `{:ok, :current}` when it is
  already there, `{:ok, :telemetry}` in ledger mode none.
  """
  @spec publish(PolicyVersion.t(), :none | {module(), keyword()}) ::
          {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.Engine.t()}
  def publish(%PolicyVersion{} = version, ledger) do
    result = appended(version, ledger)
    :telemetry.execute(@telemetry, %{}, %{version: version, result: elem(result, 1)})
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

  defp pointer(policies) do
    tables =
      policies
      |> Enum.map(& &1.table)
      |> Enum.uniq()
      |> Enum.sort()

    "policies on " <> Enum.join(tables, ", ")
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
      by: Subject.library()
    }

    case ledger.append(options, [event]) do
      {:ok, [appended]} -> {:ok, appended}
      {:error, %Error.Engine{} = error} -> {:error, error}
    end
  end

  # The latest policy version of the adapter in the ledger, paging from the start.
  defp latest(ledger, options, adapter), do: latest(ledger, options, adapter, 0, nil)

  defp latest(ledger, options, adapter, from, found) do
    case ledger.read(options, from, @page) do
      {:ok, []} -> {:ok, found}
      {:ok, events} -> latest(ledger, options, adapter, List.last(events).position, newest(events, adapter, found))
      {:error, %Error.Engine{} = error} -> {:error, error}
    end
  end

  defp newest(events, adapter, found) do
    Enum.reduce(events, found, fn
      %FactEvent{kind: :policy_version, object_ref: {:policy, ^adapter}, new: %PolicyVersion{} = new}, _acc -> new
      _other, acc -> acc
    end)
  end
end
