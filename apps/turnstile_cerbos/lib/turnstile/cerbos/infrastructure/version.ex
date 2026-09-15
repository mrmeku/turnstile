defmodule Turnstile.Cerbos.Infrastructure.Version do
  @moduledoc false
  # Publishing the policy version: resolve the binding and the
  # configuration, read the policy files the binding names, and emit the
  # version they are at as telemetry. Nothing is stored, so the event is
  # the whole of what a publication leaves behind. What a version is, and
  # what it holds, is `Turnstile.Cerbos.Version`'s.

  alias Turnstile.Cerbos.Binding
  alias Turnstile.Cerbos.Version
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.PolicyVersion

  @doc "Emit the bound directory's commit as a version, once per call, answering the version emitted."
  @spec publish(module()) :: {:ok, PolicyVersion.t()} | {:error, Error.t()}
  def publish(adapter) when is_atom(adapter) do
    with {:ok, %Binding{} = binding} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve(),
         {:ok, %PolicyVersion{} = version} <- Version.of(adapter, binding, config, config.clock.()) do
      :telemetry.execute(Version.telemetry_event(), %{}, %{version: version})

      {:ok, version}
    end
  end
end
