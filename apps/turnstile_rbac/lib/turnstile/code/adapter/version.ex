defmodule Turnstile.Code.Adapter.Version do
  @moduledoc false
  # Publishing the policy version: resolve the binding and the
  # configuration, build the version from the bound policy and the
  # configured clock, and emit it as telemetry. Nothing is stored, so the
  # event is the whole of what a publication leaves behind. What a version
  # is, and what it holds, is `Turnstile.Code.Version`'s.

  alias Turnstile.Code.Binding
  alias Turnstile.Code.Version
  alias Turnstile.Config
  alias Turnstile.Error
  alias Turnstile.PolicyVersion

  @doc "Emit the bound policy's version, once per call, answering the version emitted."
  @spec publish(module()) :: {:ok, PolicyVersion.t()} | {:error, Error.t()}
  def publish(adapter) when is_atom(adapter) do
    with {:ok, %Binding{policy: policy}} <- Binding.resolve(),
         {:ok, %Config{} = config} <- Config.resolve() do
      version = Version.of(adapter, policy, config, config.clock.())
      :telemetry.execute(Version.telemetry_event(), %{}, %{version: version})

      {:ok, version}
    end
  end
end
