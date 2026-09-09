defmodule Turnstile.Fga.Version do
  @moduledoc """
  The policy version of this adapter: the id the server gives a model when it
  is published. A model is immutable and the server keeps it, so an id names
  one text for as long as the store lives, and a decision taken under that id
  is replayed under it.

  The content is the model text the binding names, carried by value when it
  is under the cap and left as a pointer to the file above it, and the content
  hash is the digest of that text either way. The hash is what decides whether
  anything is published, because the text is the artifact under review: a text
  whose digest the ledger's latest already carries needs no second model, and
  a text that changed by a character needs one.

  `publish/1` reads that latest inside the ledger's transaction when the
  ledger offers one, so many nodes booting at once publish once. The model
  reaches the server inside that transaction, which is a side effect a
  rollback cannot take back. What a rollback leaves behind is a model no
  event names, and a model no event names is never asked under, since every
  question carries the id the configuration pins.
  """

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.FactEvent
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Client
  alias Turnstile.Id
  alias Turnstile.PolicyVersion
  alias Turnstile.Subject

  @page 1_000
  @telemetry [:turnstile, :fga, :policy_version]

  @doc "The telemetry event `publish/1` emits, once per call."
  @spec telemetry_event() :: [atom()]
  def telemetry_event, do: @telemetry

  @doc "The digest of the model text."
  @spec content_hash(String.t()) :: String.t()
  def content_hash(text) when is_binary(text), do: Base.encode16(:crypto.hash(:sha256, text), case: :lower)

  @doc """
  The version the ledger records for a model that has been published.
  Requires `author:`, `approval:`, `at:`, `path:`, and `content_bytes:`.
  """
  @spec of(module(), Client.model(), String.t(), keyword()) :: PolicyVersion.t()
  def of(adapter, model, text, options) when is_atom(adapter) and is_binary(model) and is_binary(text) do
    carried? = byte_size(text) <= Keyword.fetch!(options, :content_bytes)

    %PolicyVersion{
      adapter: adapter,
      version: model,
      content_hash: content_hash(text),
      content: if(carried?, do: text),
      pointer: if(carried?, do: nil, else: "the model in #{Keyword.fetch!(options, :path)}"),
      author: Keyword.fetch!(options, :author),
      approval: Keyword.fetch!(options, :approval),
      at: Keyword.fetch!(options, :at)
    }
  end

  @doc """
  Publish the bound model unless the ledger's latest for the adapter carries
  the digest of its text: `{:ok, event}` when the model was written and the
  version appended, `{:ok, :current}` when the ledger already names that
  text.
  """
  @spec publish(module()) ::
          {:ok, :current | FactEvent.t()}
          | {:error, Error.Invalid.t() | Error.Unsupported.t() | Error.Engine.t()}
  def publish(adapter) when is_atom(adapter) do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve(),
         {:ok, ledger} <- ledger(adapter, config),
         {:ok, options} <- entry(adapter, config),
         {:ok, text} <- Binding.text(binding) do
      reported(%{adapter: adapter, binding: binding, config: config, options: options, text: text}, ledger)
    end
  end

  # One telemetry event per call, whatever the publication answers.
  defp reported(publication, ledger) do
    result = published(publication, ledger)
    metadata = %{adapter: publication.adapter, hash: content_hash(publication.text), result: elem(result, 1)}
    :telemetry.execute(@telemetry, %{}, metadata)

    result
  end

  defp entry(adapter, %Config{} = config) do
    case Config.adapter(config) do
      {^adapter, options} -> {:ok, options}
      {other, _options} -> {:error, invalid("#{inspect(other)} is the configured adapter, not #{inspect(adapter)}")}
    end
  end

  defp ledger(adapter, %Config{ledger: :none}) do
    {:error, %Error.Unsupported{adapter: adapter, feature: :ledger_mode_none, note: "there is nothing to publish into"}}
  end

  defp ledger(_adapter, %Config{ledger: {module, options}}), do: {:ok, {module, options}}

  defp published(publication, {ledger, options}) do
    within(ledger, options, fn ->
      with {:ok, latest} <- latest(ledger, options, publication.adapter) do
        appended(publication, {ledger, options}, latest)
      end
    end)
  end

  defp within(ledger, options, fun) do
    if function_exported?(ledger, :transaction, 2), do: ledger.transaction(options, fun), else: fun.()
  end

  defp appended(publication, ledger, latest) do
    if latest && latest.content_hash == content_hash(publication.text) do
      {:ok, :current}
    else
      written(publication, ledger, latest)
    end
  end

  defp written(publication, {ledger, options}, latest) do
    with {:ok, model} <- Binding.compiled(publication.binding),
         {:ok, id} <- writes(publication.options, model) do
      append(ledger, options, version(publication, id), latest)
    end
  end

  defp writes(options, model) do
    client = Keyword.get(options, :client, Client.Http)

    client.write_model(Keyword.fetch!(options, :endpoint), Keyword.fetch!(options, :store_id), model)
  end

  defp version(publication, model) do
    of(publication.adapter, model, publication.text,
      author: publication.binding.author,
      approval: publication.binding.approval,
      at: publication.config.clock.now(),
      path: publication.binding.model,
      content_bytes: publication.config.caps[:policy_content_bytes]
    )
  end

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

  defp invalid(detail), do: %Error.Invalid{what: :model, detail: detail}
end
