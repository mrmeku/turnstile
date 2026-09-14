defmodule Turnstile.Fga.Adapter.Version do
  @moduledoc false
  # Publishing the bound model: read the model text the binding names,
  # compile it, write it to the server, and emit the version the server
  # gave it as telemetry. Nothing is stored, so the event is the whole of
  # what a publication leaves behind, and every call writes a model: a
  # model is immutable and the server keeps every one, so nothing here can
  # tell a text that has been published before from one that has not. What
  # a version is, and what it holds, is `Turnstile.Fga.Version`'s.

  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.Fga.Adapter.Store
  alias Turnstile.Fga.Binding
  alias Turnstile.Fga.Version
  alias Turnstile.PolicyVersion

  @doc "Write the bound model to the server and emit the version it was published under."
  @spec publish(module()) :: {:ok, PolicyVersion.t()} | {:error, Error.t()}
  def publish(adapter) when is_atom(adapter) do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve(),
         {:ok, text} <- Binding.text(binding),
         {:ok, id} <- written(adapter, binding) do
      {:ok, emitted(version(adapter, binding, config, {id, text}))}
    end
  end

  # The bound text compiled and written to the store the configuration
  # names, which answers with the id it keeps that model under.
  defp written(adapter, %Binding{} = binding) do
    with {:ok, %Store{} = store} <- Store.resolve(adapter),
         {:ok, model} <- Binding.compiled(binding) do
      store.client.write_model(store.endpoint, store.store, model)
    end
  end

  defp version(adapter, %Binding{} = binding, %Config{} = config, {id, text}) do
    Version.of(adapter, id, text,
      author: binding.author,
      approval: binding.approval,
      at: config.clock.(),
      path: binding.model,
      content_bytes: config.caps[:policy_content_bytes]
    )
  end

  defp emitted(%PolicyVersion{} = version) do
    :telemetry.execute(Version.telemetry_event(), %{}, %{version: version})

    version
  end
end
