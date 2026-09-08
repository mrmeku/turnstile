defmodule Turnstile.Code.Version do
  @moduledoc """
  The policy version of RBAC in code. Its identifier is the `version:` the
  policy module gave, or the content hash: a digest of the policy module and
  every predicate module, so a change to a rule is a new version whether or
  not anyone said so. The content is the role table and the module list as
  text when it is under the configured cap, and a pointer to the modules
  otherwise. One event per version: `publish/0` reads the ledger's latest
  policy version for this adapter and appends only when it is older or
  missing, inside the ledger's transaction when it offers one, so many nodes
  booting at once append it once. In ledger mode none it emits the
  telemetry event `[:turnstile, :code, :policy_version]` and appends
  nothing.
  """

  alias Turnstile.Code.Binding
  alias Turnstile.Code.Policy
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Id
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject

  @page 1_000
  @telemetry [:turnstile, :code, :policy_version]

  @doc "The telemetry event `publish/0` emits."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc "The version identifier a decision names."
  @spec ref(Policy.t()) :: PolicyVersion.ref()
  def ref(policy) when is_atom(policy), do: Policy.options(policy)[:version] || content_hash(policy)

  @doc "The digest of the policy module and every predicate module."
  @spec content_hash(Policy.t()) :: String.t()
  def content_hash(policy) when is_atom(policy) do
    digest = Enum.map_join(Policy.modules(policy), "", &(&1.module_info(:md5) <> Atom.to_string(&1)))
    Base.encode16(:crypto.hash(:sha256, digest), case: :lower)
  end

  @doc "The role table and the module list as text."
  @spec content(Policy.t()) :: String.t()
  def content(policy) when is_atom(policy) do
    roles =
      Enum.map_join(Policy.table(policy), "", fn {name, permissions} -> "  #{name}: #{Enum.join(permissions, ", ")}\n" end)

    "modules: #{Enum.map_join(Policy.modules(policy), ", ", &inspect/1)}\nroles:\n" <> roles
  end

  @doc "The version as the ledger records it for `adapter`, with the content by value when under the cap."
  @spec of(module(), Policy.t(), Config.t(), DateTime.t()) :: PolicyVersion.t()
  def of(adapter, policy, %Config{caps: caps}, %DateTime{} = at) when is_atom(adapter) and is_atom(policy) do
    options = Policy.options(policy)
    text = content(policy)
    under_cap? = byte_size(text) <= caps[:policy_content_bytes]

    %PolicyVersion{
      adapter: adapter,
      version: ref(policy),
      content_hash: content_hash(policy),
      content: if(under_cap?, do: text),
      pointer: if(under_cap?, do: nil, else: "modules " <> Enum.map_join(Policy.modules(policy), ", ", &inspect/1)),
      author: options[:author],
      approval: options[:approval],
      at: at
    }
  end

  @doc """
  Append the bound policy's version when the ledger's latest is older or
  missing: `{:ok, event}` when appended, `{:ok, :current}` when the ledger
  already names it, `{:ok, :telemetry}` in ledger mode none.
  """
  @spec publish(module()) ::
          {:ok, :telemetry | :current | FactEvent.t()} | {:error, Error.Invalid.t() | Error.Engine.t()}
  def publish(adapter) when is_atom(adapter) do
    with {:ok, %Binding{policy: policy}} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve() do
      version = of(adapter, policy, config, config.clock.now())
      result = publish(version, config.ledger)
      :telemetry.execute(@telemetry, %{}, %{version: version, result: elem(result, 1)})
      result
    end
  end

  defp publish(_version, :none), do: {:ok, :telemetry}

  defp publish(%PolicyVersion{adapter: adapter} = version, {ledger, options}) do
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
